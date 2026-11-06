import Foundation
import Network

public struct TokenTelemetryConnection: Equatable, Sendable {
    public let endpoint: URL
    public let authorizationHeader: String
    public init(endpoint: URL, authorizationHeader: String) {
        self.endpoint = endpoint; self.authorizationHeader = authorizationHeader
    }
}

public protocol TokenTelemetryReceiving: AnyObject, Sendable {
    func start(accountKey: String) async throws -> TokenTelemetryConnection
    func stop()
}

/// Memory-only receiver bound to a temporary measurement scope.
public final class TokenTelemetryReceiver: TokenTelemetryReceiving, @unchecked Sendable {
    private let queue = DispatchQueue(label: "HappyLulu.token-telemetry")
    private let queueKey = DispatchSpecificKey<Bool>()
    private let onSamples: @Sendable ([TokenSpeedSample]) -> Void
    private let provider: UsageProviderKind
    private var path: String {
        switch provider {
        case .claude: return "/unsupported"
        case .codex: return "/v1/traces"
        case .antigravity: return "/v1/samples"
        }
    }
    static func maximumBodyBytes(for provider: UsageProviderKind) -> Int {
        switch provider {
        case .codex: return CodexTokenSpeedTracker.maximumPayloadBytes
        case .claude: return 0
        case .antigravity: return 8192
        }
    }
    // All mutable state is confined to queue.
    private var listener: NWListener?
    private var pendingStart: CheckedContinuation<TokenTelemetryConnection, Error>?
    private var activeRequestID: UUID?
    private var generation = 0
    private var accountKey = ""
    private var authorizationHeader = ""
    private var connections: [ObjectIdentifier: Connection] = [:]
    private var delivered: [String: Date] = [:]
    private var codexTracker: CodexTokenSpeedTracker?

    public init(provider: UsageProviderKind = .codex, onSamples: @escaping @Sendable ([TokenSpeedSample]) -> Void) {
        self.provider = provider; self.onSamples = onSamples
        queue.setSpecific(key: queueKey, value: true)
    }

    public func start(accountKey: String) async throws -> TokenTelemetryConnection {
        let request = StartRequest()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let value: TokenTelemetryConnection = try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    guard !request.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                    guard self.listener == nil else { continuation.resume(throwing: TokenSpeedError.alreadyRunning); return }
                    let validScope: Bool
                    switch self.provider {
                    case .claude: validScope = false
                    case .codex: validScope = accountKey.hasPrefix("codex-profile:") && accountKey.utf8.count <= 128 && accountKey.count > 14
                    case .antigravity: validScope = accountKey.hasPrefix("antigravity:") && UUID(uuidString: String(accountKey.dropFirst(12))) != nil
                    }
                    guard validScope, !accountKey.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                        continuation.resume(throwing: TokenSpeedError.invalidAccount); return
                    }
                    do {
                        let tracker = self.provider == .codex ? try CodexTokenSpeedTracker(accountKey: accountKey) : nil
                        let parameters = NWParameters.tcp
                        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
                        let listener = try NWListener(using: parameters)
                        self.listener = listener; self.pendingStart = continuation
                        self.activeRequestID = request.id
                        self.accountKey = accountKey
                        self.codexTracker = tracker
                        self.authorizationHeader = "Bearer " + UUID().uuidString + UUID().uuidString
                        self.generation += 1
                        let current = self.generation
                        listener.stateUpdateHandler = { [weak self] state in self?.listenerChanged(state, generation: current) }
                        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection, generation: current) }
                        listener.start(queue: self.queue)
                        self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                            guard let self, self.generation == current, self.pendingStart != nil else { return }
                            self.failStart()
                        }
                    } catch { continuation.resume(throwing: TokenSpeedError.unavailable) }
                }
            }
            try Task.checkCancellation()
            return value
        } onCancel: {
            request.cancel()
            self.queue.async { [self] in
                if self.activeRequestID == request.id { self.stopOnQueue() }
            }
        }
    }

    public func stop() {
        if DispatchQueue.getSpecific(key: queueKey) == true { stopOnQueue() }
        else { queue.sync { stopOnQueue() } }
    }

    private func stopOnQueue() {
        generation += 1
        listener?.cancel(); listener = nil
        let pending = pendingStart; pendingStart = nil
        activeRequestID = nil
        pending?.resume(throwing: CancellationError())
        for state in connections.values { state.connection.cancel() }
        connections.removeAll(); delivered.removeAll()
        codexTracker = nil
        accountKey = ""; authorizationHeader = ""
    }

    private final class StartRequest: @unchecked Sendable {
        let id = UUID()
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    }

    private func listenerChanged(_ state: NWListener.State, generation current: Int) {
        guard generation == current else { return }
        switch state {
        case .ready:
            guard let port = listener?.port,
                  let endpoint = URL(string: "http://127.0.0.1:\(port.rawValue)\(path)") else {
                failStart(); return
            }
            let pending = pendingStart; pendingStart = nil
            pending?.resume(returning: TokenTelemetryConnection(endpoint: endpoint, authorizationHeader: authorizationHeader))
        case .failed: failStart()
        default: break
        }
    }

    private func failStart() {
        let pending = pendingStart; pendingStart = nil
        stopOnQueue()
        pending?.resume(throwing: TokenSpeedError.unavailable)
    }

    private final class Connection: @unchecked Sendable {
        let connection: NWConnection
        var input = Data()
        init(_ connection: NWConnection) { self.connection = connection }
    }

    private func accept(_ connection: NWConnection, generation current: Int) {
        guard generation == current, connections.count < 4,
              case .hostPort(let host, _) = connection.endpoint, host == .ipv4(.loopback) else {
            connection.cancel(); return
        }
        let id = ObjectIdentifier(connection)
        connections[id] = Connection(connection)
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.generation == current else { return }
            self.close(id)
        }
        receive(id, generation: current)
    }

    private func receive(_ id: ObjectIdentifier, generation current: Int) {
        guard let state = connections[id], generation == current else { return }
        state.connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, completed, error in
            guard let self, self.generation == current, let state = self.connections[id] else { return }
            if let data { state.input.append(data) }
            switch TokenTelemetryHTTPRequest.parse(state.input, authorizationHeader: self.authorizationHeader,
                path: self.path, maximumBodyBytes: Self.maximumBodyBytes(for: self.provider)) {
            case .incomplete:
                if completed || error != nil { self.close(id) }
                else { self.receive(id, generation: current) }
            case .rejected(let status): self.respond(status, id: id)
            case .ready(let body):
                do {
                    let now = Date()
                    let samples: [TokenSpeedSample]
                    switch self.provider {
                    case .claude: throw TokenSpeedError.invalidAccount
                    case .codex:
                        guard self.codexTracker != nil else { throw TokenSpeedError.unavailable }
                        samples = try self.codexTracker?.ingestOTLP(data: body, now: now) ?? []
                    case .antigravity:
                        samples = [try TokenTelemetrySamplePayload.parse(body, expectedScope: self.accountKey, now: now)]
                    }
                    self.delivered = self.delivered.filter { now.timeIntervalSince($0.value) <= TokenSpeed.maximumAge }
                    var fresh: [TokenSpeedSample] = []
                    for sample in samples where self.delivered[sample.requestKey] == nil {
                        self.delivered[sample.requestKey] = sample.recordedAt; fresh.append(sample)
                    }
                    if self.delivered.count > 1024 {
                        let keep = self.delivered.sorted { $0.value > $1.value }.prefix(1024)
                        self.delivered = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
                    }
                    if !fresh.isEmpty { self.onSamples(fresh) }
                    self.respond(200, id: id)
                } catch { self.respond(400, id: id) }
            }
        }
    }

    private func respond(_ status: Int, id: ObjectIdentifier) {
        guard let state = connections[id] else { return }
        let body = status == 200 ? "{}" : ""
        let response = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Rejected")\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
        state.connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            self?.close(id)
        })
    }

    private func close(_ id: ObjectIdentifier) {
        connections.removeValue(forKey: id)?.connection.cancel()
    }

    deinit {
        listener?.cancel()
        for state in connections.values { state.connection.cancel() }
    }
}

enum TokenTelemetryHTTPRequest {
    enum Result: Equatable { case incomplete, ready(Data), rejected(Int) }

    static func parse(_ data: Data, authorizationHeader: String, path: String = "/v1/traces",
                      maximumBodyBytes: Int = TokenSpeed.maximumPayloadBytes) -> Result {
        guard let boundary = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > 16_384 ? .rejected(431) : .incomplete
        }
        guard boundary.lowerBound <= 16_384 else { return .rejected(431) }
        guard let header = String(data: data[..<boundary.lowerBound], encoding: .ascii) else { return .rejected(400) }
        let lines = header.components(separatedBy: "\r\n")
        guard let first = lines.first else { return .rejected(400) }
        let request = first.split(separator: " ", omittingEmptySubsequences: false)
        guard request.count == 3, request[2] == "HTTP/1.1" else { return .rejected(400) }
        guard request[0] == "POST" else { return .rejected(405) }
        guard request[1] == Substring(path) else { return .rejected(404) }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { return .rejected(400) }
            let key = line[..<colon].lowercased()
            guard key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }), headers[key] == nil else { return .rejected(400) }
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["authorization"] == authorizationHeader else { return .rejected(401) }
        guard headers["transfer-encoding"] == nil else { return .rejected(400) }
        guard headers["content-encoding"] == nil,
              headers["content-type"]?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else { return .rejected(415) }
        guard let rawLength = headers["content-length"], !rawLength.isEmpty,
              rawLength.allSatisfy({ $0.isASCII && $0.isNumber }), let length = Int(rawLength) else { return .rejected(400) }
        guard length <= maximumBodyBytes else { return .rejected(413) }
        let body = data[boundary.upperBound...]
        guard body.count <= length else { return .rejected(400) }
        return body.count == length ? .ready(Data(body)) : .incomplete
    }
}

enum TokenTelemetrySamplePayload {
    private struct Sample: Decodable {
        let version: Int
        let outputTokens: Int
        let durationMilliseconds: Double
        let recordedAt: Double
        let scopeKey: String
        let requestKey: String
    }

    static func parse(_ data: Data, expectedScope: String, now: Date) throws -> TokenSpeedSample {
        guard data.count <= 8192, let value = try? JSONDecoder().decode(Sample.self, from: data),
              value.version == 1, value.scopeKey == expectedScope,
              value.recordedAt.isFinite, value.recordedAt <= now.timeIntervalSince1970,
              now.timeIntervalSince1970 - value.recordedAt <= TokenSpeed.maximumAge,
              let sample = TokenSpeedSample(outputTokens: value.outputTokens, durationMilliseconds: value.durationMilliseconds,
                  recordedAt: Date(timeIntervalSince1970: value.recordedAt), accountKey: value.scopeKey,
                  requestKey: value.requestKey) else { throw TokenSpeedError.invalidPayload }
        return sample
    }
}
