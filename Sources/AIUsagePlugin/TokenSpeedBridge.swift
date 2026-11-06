import Foundation

/// Preserves a headless CLI's stdout while forwarding only validated numeric measurements.
public enum TokenSpeedBridge {
    private static let maximumLineBytes = 1_048_576

    public static func run(provider: String, environment: [String: String] = ProcessInfo.processInfo.environment,
                           input: FileHandle = .standardInput, output: FileHandle = .standardOutput) async -> Int32 {
        let configuration = provider == "antigravity" ? try? Configuration(environment: environment) : nil
        guard let configuration else {
            warning()
            do { try copy(input: input, output: output); return 0 } catch { return 74 }
        }
        let delivery = Delivery(configuration: configuration)
        do {
            try await forward(input: input, output: output, scopeKey: configuration.scopeKey) {
                await delivery.offer($0)
            }
            await delivery.finish()
            return 0
        } catch {
            await delivery.finish()
            return 74
        }
    }

    struct Configuration: Sendable {
        let endpoint: URL
        let authorization: String
        let scopeKey: String

        init(environment: [String: String]) throws {
            guard let raw = environment["HAPPY_LULU_TOKEN_ENDPOINT"],
                  let parts = URLComponents(string: raw), parts.scheme == "http", parts.host == "127.0.0.1",
                  let port = parts.port, (1...65535).contains(port), parts.path == "/v1/samples",
                  parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
                  let endpoint = parts.url,
                  let authorization = environment["HAPPY_LULU_TOKEN_AUTH"], authorization.hasPrefix("Bearer "),
                  (8...256).contains(authorization.utf8.count),
                  authorization.dropFirst(7).allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
                  let scopeKey = environment["HAPPY_LULU_TOKEN_SCOPE"], scopeKey.hasPrefix("antigravity:"),
                  UUID(uuidString: String(scopeKey.dropFirst("antigravity:".count))) != nil else {
                throw TokenSpeedError.invalidPayload
            }
            self.endpoint = endpoint; self.authorization = authorization; self.scopeKey = scopeKey
        }
    }

    static func forward(input: FileHandle, output: FileHandle, scopeKey: String,
                        deliver: @Sendable (TokenSpeedSample) async -> Void) async throws {
        var stream = try AntigravityTokenSpeedStream(scopeKey: scopeKey)
        var line = Data()
        var skippingLine = false
        while let chunk = try input.read(upToCount: 16_384), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
            let parts = chunk.split(separator: 0x0A, omittingEmptySubsequences: false)
            for (index, part) in parts.enumerated() {
                let endsLine = index < parts.count - 1
                if !skippingLine {
                    if line.count + part.count > maximumLineBytes {
                        line.removeAll(keepingCapacity: false); skippingLine = true
                    } else { line.append(contentsOf: part) }
                }
                if endsLine {
                    if !skippingLine, let sample = consume(line, stream: &stream) { await deliver(sample) }
                    line.removeAll(keepingCapacity: true); skippingLine = false
                }
            }
        }
        if !skippingLine, let sample = consume(line, stream: &stream) { await deliver(sample) }
    }

    static func samplePayload(_ sample: TokenSpeedSample) throws -> Data {
        let payload = Sample(version: 1, outputTokens: sample.outputTokens,
            durationMilliseconds: sample.durationMilliseconds, recordedAt: sample.recordedAt.timeIntervalSince1970,
            scopeKey: sample.accountKey, requestKey: sample.requestKey)
        let data = try JSONEncoder().encode(payload)
        guard data.count <= 8192 else { throw TokenSpeedError.invalidPayload }
        return data
    }

    private static func consume(_ line: Data, stream: inout AntigravityTokenSpeedStream) -> TokenSpeedSample? {
        guard !line.isEmpty else { return nil }
        return try? stream.consume(line: line)
    }

    private static func copy(input: FileHandle, output: FileHandle) throws {
        while let chunk = try input.read(upToCount: 16_384), !chunk.isEmpty { try output.write(contentsOf: chunk) }
    }

    private static func warning() {
        try? FileHandle.standardError.write(contentsOf: Data("HappyLulu: token speed measurement is unavailable; CLI output continues.\n".utf8))
    }

    private struct Sample: Encodable {
        let version: Int
        let outputTokens: Int
        let durationMilliseconds: Double
        let recordedAt: Double
        let scopeKey: String
        let requestKey: String
    }

    private actor Delivery {
        private let client: HTTPClient
        private var tasks: [UUID: Task<Void, Never>] = [:]
        init(configuration: Configuration) { client = HTTPClient(configuration: configuration) }

        func offer(_ sample: TokenSpeedSample) {
            guard tasks.count < 4, let body = try? TokenSpeedBridge.samplePayload(sample) else { return }
            let id = UUID()
            tasks[id] = Task {
                await client.send(body)
                tasks.removeValue(forKey: id)
            }
        }

        func finish() async {
            for task in Array(tasks.values) { await task.value }
            client.invalidate()
        }
    }

    /// The receiver's response body is unnecessary, so cancel as soon as headers arrive.
    private final class HTTPClient: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let configuration: Configuration
        private let lock = NSLock()
        private var pending: [Int: CheckedContinuation<Void, Never>] = [:]
        private var session: URLSession!

        init(configuration: Configuration) {
            self.configuration = configuration
            super.init()
            let options = URLSessionConfiguration.ephemeral
            options.connectionProxyDictionary = [:]
            options.httpCookieStorage = nil; options.urlCredentialStorage = nil; options.urlCache = nil
            options.timeoutIntervalForRequest = 3; options.timeoutIntervalForResource = 4
            options.httpMaximumConnectionsPerHost = 4
            session = URLSession(configuration: options, delegate: self, delegateQueue: nil)
        }

        func send(_ body: Data) async {
            await withCheckedContinuation { continuation in
                var request = URLRequest(url: configuration.endpoint)
                request.httpMethod = "POST"; request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
                request.setValue(configuration.authorization, forHTTPHeaderField: "Authorization")
                let task = session.dataTask(with: request)
                lock.lock(); pending[task.taskIdentifier] = continuation; lock.unlock()
                task.resume()
            }
        }

        func invalidate() { session.finishTasksAndInvalidate() }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
            completionHandler(.cancel)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            lock.lock(); let continuation = pending.removeValue(forKey: task.taskIdentifier); lock.unlock()
            continuation?.resume()
        }
    }
}
