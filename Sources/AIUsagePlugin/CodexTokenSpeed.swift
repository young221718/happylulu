import Foundation
import CryptoKit

/// Joins Codex's completed response span to its direct receiving_stream parent.
/// The interval includes stream waiting/handling and output includes reasoning tokens.
/// A dedicated authenticated collector must bind this tracker to the selected profile;
/// traces themselves do not prove the signed-in account and existing sessions are not attached.
public struct CodexTokenSpeedTracker: Sendable {
    public static let maximumPayloadBytes = 4_194_304
    private let accountKey: String
    private var spans: [String: Span] = [:]
    private var emitted: [String: Date] = [:]
    private static let services: Set<String> = ["Codex Desktop", "codex_cli_rs", "codex-tui", "codex_exec", "codex-app-server",
        "codex_desktop", "codex_vscode", "codex_sdk_ts", "codex-app-server-sdk", "codex-cli", "codex"]
    private static let maximumSpans = 2048

    public init(accountKey: String) throws {
        guard !accountKey.isEmpty, accountKey.utf8.count <= 128 else { throw TokenSpeedError.invalidAccount }
        self.accountKey = accountKey
    }

    /// Supports split and out-of-order OTLP HTTP/JSON exports without reading content fields.
    public mutating func ingestOTLP(data: Data, now: Date = Date()) throws -> [TokenSpeedSample] {
        guard now.timeIntervalSince1970.isFinite, now.timeIntervalSince1970 > 0,
              data.count <= Self.maximumPayloadBytes,
              let request = try? JSONDecoder().decode(TracesRequest.self, from: data),
              request.resourceSpans.count <= 32 else { throw TokenSpeedError.invalidPayload }
        var next = spans.filter { now.timeIntervalSince($0.value.endDate) <= TokenSpeed.maximumAge }
        var nextEmitted = emitted.filter { now.timeIntervalSince($0.value) <= TokenSpeed.maximumAge }
        var count = 0
        for resource in request.resourceSpans {
            guard let service = try Self.attributes(resource.resource?.attributes ?? [])["service.name"]?.string,
                  Self.services.contains(service) else { continue }
            guard resource.scopeSpans.count <= 64 else { throw TokenSpeedError.invalidPayload }
            for scope in resource.scopeSpans {
                count += scope.spans.count
                guard count <= Self.maximumSpans else { throw TokenSpeedError.invalidPayload }
                for raw in scope.spans {
                    guard raw.name == "receiving_stream" || raw.name == "completed" || raw.name == "handle_responses" else { continue }
                    guard let value = try Span(raw, now: now) else { continue }
                    if let previous = next[value.key], previous != value { throw TokenSpeedError.invalidPayload }
                    next[value.key] = value
                }
            }
        }
        guard next.count <= Self.maximumSpans else { throw TokenSpeedError.invalidPayload }
        let completions = next.values.filter { $0.name == "completed" && $0.outputTokens != nil }
        var byParent: [String: Span] = [:]
        for child in completions {
            let parentKey = child.parentKey
            if let previous = byParent[parentKey], previous.key != child.key { throw TokenSpeedError.invalidPayload }
            byParent[parentKey] = child
        }
        var samples: [TokenSpeedSample] = []
        for (parentKey, child) in byParent {
            guard nextEmitted[parentKey] == nil, let parent = next[parentKey], parent.name == "receiving_stream",
                  !parent.failed, !child.failed, parent.start <= child.start, child.end <= parent.end,
                  parent.start < child.end, let tokens = child.outputTokens else { continue }
            let duration = Double(child.end - parent.start) / 1_000_000
            guard let sample = TokenSpeedSample(outputTokens: tokens, durationMilliseconds: duration,
                recordedAt: child.endDate, accountKey: accountKey,
                requestKey: Self.fingerprint(accountKey + "|" + parentKey)) else { continue }
            samples.append(sample)
            nextEmitted[parentKey] = child.endDate
        }
        guard nextEmitted.count <= Self.maximumSpans else { throw TokenSpeedError.invalidPayload }
        spans = next
        emitted = nextEmitted
        return samples.sorted { $0.recordedAt < $1.recordedAt }
    }

    private static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func identifier(_ value: String, length: Int) -> Bool {
        value.utf8.count == length && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) || (65...70).contains($0) }
            && value.utf8.contains { $0 != 48 }
    }

    private static func attributes(_ raw: [Attribute]) throws -> [String: Scalar] {
        guard raw.count <= 128 else { throw TokenSpeedError.invalidPayload }
        var values: [String: Scalar] = [:]
        for entry in raw {
            guard let value = entry.value else { continue }
            guard values.updateValue(value, forKey: entry.key) == nil else { throw TokenSpeedError.invalidPayload }
        }
        return values
    }

    private struct Span: Equatable, Sendable {
        let traceID: String
        let id: String
        let parentID: String
        let name: String
        let start: UInt64
        let end: UInt64
        let outputTokens: Int?
        let failed: Bool
        var key: String { traceID + ":" + id }
        var parentKey: String { traceID + ":" + parentID }
        var endDate: Date { Date(timeIntervalSince1970: Double(end) / 1_000_000_000) }

        init?(_ raw: RawSpan, now: Date) throws {
            guard Self.validID(raw.traceId, length: 32), Self.validID(raw.spanId, length: 16),
                  raw.parentSpanId.map({ Self.validID($0, length: 16) }) ?? true,
                  let start = UInt64(raw.startTimeUnixNano), let end = UInt64(raw.endTimeUnixNano), end >= start else {
                throw TokenSpeedError.invalidPayload
            }
            let endDate = Date(timeIntervalSince1970: Double(end) / 1_000_000_000)
            guard endDate <= now, now.timeIntervalSince(endDate) <= TokenSpeed.maximumAge,
                  end - start <= 3_600_000_000_000 else { return nil }
            let values = try CodexTokenSpeedTracker.attributes(raw.attributes ?? [])
            let tokens: Int?
            if raw.name == "completed" || raw.name == "handle_responses" {
                guard let value = values["gen_ai.usage.output_tokens"]?.integer,
                      (0...100_000_000).contains(value) else { return nil }
                tokens = value
                guard raw.parentSpanId != nil else { return nil }
            } else { tokens = nil }
            self.traceID = raw.traceId.lowercased(); self.id = raw.spanId.lowercased()
            self.parentID = raw.parentSpanId?.lowercased() ?? ""
            // Some Codex releases retain the source span name despite recording otel.name="completed".
            self.name = raw.name == "handle_responses" ? "completed" : raw.name
            self.start = start; self.end = end
            self.outputTokens = tokens; self.failed = raw.status?.failed ?? false
        }
        private static func validID(_ value: String, length: Int) -> Bool {
            CodexTokenSpeedTracker.identifier(value, length: length)
        }
    }

    private struct TracesRequest: Decodable { let resourceSpans: [ResourceSpans] }
    private struct ResourceSpans: Decodable {
        struct Resource: Decodable { let attributes: [Attribute]? }
        let resource: Resource?
        let scopeSpans: [ScopeSpans]
    }
    private struct ScopeSpans: Decodable { let spans: [RawSpan] }
    private struct RawSpan: Decodable {
        let traceId: String
        let spanId: String
        let parentSpanId: String?
        let name: String
        let startTimeUnixNano: String
        let endTimeUnixNano: String
        let attributes: [Attribute]?
        let status: Status?
    }
    private struct Status: Decodable {
        let failed: Bool
        private enum CodingKeys: String, CodingKey { case code }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let value = try? container.decode(Int.self, forKey: .code) { failed = value == 2 }
            else if let value = try? container.decode(String.self, forKey: .code) { failed = value == "STATUS_CODE_ERROR" }
            else { failed = false }
        }
    }
    private struct Scalar: Decodable, Equatable {
        let stringValue: String?
        let intValue: String?
        var string: String? { stringValue }
        var integer: Int? { intValue.flatMap(Int.init) }
    }
    private struct Attribute: Decodable {
        let key: String
        let value: Scalar?
        private enum CodingKeys: String, CodingKey { case key, value }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            key = try container.decode(String.self, forKey: .key)
            // Other attributes can contain prompts, paths, email, or tools; never materialize them.
            value = ["service.name", "gen_ai.usage.output_tokens"].contains(key)
                ? try container.decode(Scalar.self, forKey: .value) : nil
        }
    }
}
