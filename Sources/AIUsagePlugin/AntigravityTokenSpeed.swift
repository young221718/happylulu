import Foundation
import CryptoKit

public enum AntigravityTokenSpeedError: Error, Equatable, Sendable {
    case invalidPayload, invalidScope, missingSession, sessionMismatch, conflictingStep
}

/// Consumes live `agy --output-format stream-json` lines without retaining response or tool content.
/// A scope identifies this opt-in measurement connection, not an authenticated Antigravity account.
public struct AntigravityTokenSpeedStream: Sendable {
    public let scopeKey: String
    private var conversation: UUID?
    private var completedSteps: [Int: Metrics] = [:]
    private static let maximumLineBytes = 1_048_576
    private static let maximumSteps = 4096

    public init(scopeKey: String) throws {
        guard scopeKey.hasPrefix("antigravity:"), scopeKey.count > "antigravity:".count,
              scopeKey.utf8.count <= 128 else { throw AntigravityTokenSpeedError.invalidScope }
        self.scopeKey = scopeKey
    }

    /// Uses a single completed agent-response step's tokens and duration, never cumulative result counters.
    /// `receivedAt` is this live receiver's observation time; the CLI event supplies no wall-clock timestamp.
    public mutating func consume(line: Data, receivedAt: Date = Date()) throws -> TokenSpeedSample? {
        guard !line.isEmpty, line.count <= Self.maximumLineBytes,
              receivedAt.timeIntervalSince1970.isFinite,
              let event = try? JSONDecoder().decode(Event.self, from: line) else {
            throw AntigravityTokenSpeedError.invalidPayload
        }
        switch event.event {
        case "init":
            guard let value = event.conversationID, let id = UUID(uuidString: value) else {
                throw AntigravityTokenSpeedError.invalidPayload
            }
            if let conversation, conversation != id { throw AntigravityTokenSpeedError.sessionMismatch }
            conversation = id
            return nil
        case "step_update":
            guard let conversation else { throw AntigravityTokenSpeedError.missingSession }
            guard let step = event.step, let id = UUID(uuidString: step.conversationID),
                  (0...1_000_000_000).contains(step.index) else {
                throw AntigravityTokenSpeedError.invalidPayload
            }
            guard id == conversation else { throw AntigravityTokenSpeedError.sessionMismatch }
            guard step.state == "DONE", step.type == "agent_response" else { return nil }
            // The CLI documents both metrics as optional; missing metrics must not invent a rate.
            guard let output = step.usage?.outputTokens, let duration = step.duration else { return nil }
            let metrics = Metrics(outputTokens: output, duration: duration)
            if let previous = completedSteps[step.index] {
                guard previous == metrics else { throw AntigravityTokenSpeedError.conflictingStep }
                return nil
            }
            let request = scopeKey + "|" + conversation.uuidString + "|" + String(step.index)
            guard let sample = TokenSpeedSample(outputTokens: output, durationMilliseconds: duration * 1000,
                recordedAt: receivedAt, accountKey: scopeKey, requestKey: Self.fingerprint(request)),
                completedSteps.count < Self.maximumSteps else { throw AntigravityTokenSpeedError.invalidPayload }
            completedSteps[step.index] = metrics
            return sample
        default:
            return nil
        }
    }

    private static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private struct Metrics: Equatable, Sendable {
        let outputTokens: Int
        let duration: Double
    }
    private struct Event: Decodable {
        let event: String
        let conversationID: String?
        let step: Step?
        private enum CodingKeys: String, CodingKey {
            case event, conversationID = "conversation_id", step = "step_update"
        }
    }
    private struct Step: Decodable {
        let conversationID: String
        let index: Int
        let state: String
        let type: String
        let duration: Double?
        let usage: Usage?
        private enum CodingKeys: String, CodingKey {
            case conversationID = "conversation_id", index = "step_index", state, type = "step_type"
            case duration = "duration_seconds", usage
        }
    }
    private struct Usage: Decodable {
        let outputTokens: Int?
        private enum CodingKeys: String, CodingKey { case outputTokens = "output_tokens" }
    }
}
