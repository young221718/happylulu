import XCTest
@testable import AIUsagePlugin

final class TokenTelemetryReceiverTests: XCTestCase {
    private let authorization = "Bearer synthetic-secret"

    private func request(_ body: String = "{}", method: String = "POST", path: String = "/v1/traces",
                         authorization: String? = "Bearer synthetic-secret", extra: String = "") -> Data {
        var header = "\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n"
        if let authorization { header += "Authorization: \(authorization)\r\n" }
        return Data((header + extra + "\r\n" + body).utf8)
    }

    func testLegacyUnsupportedProviderCannotStartAListener() async throws {
        let receiver = TokenTelemetryReceiver(provider: .claude) { _ in XCTFail("Unsupported connection received a sample") }
        defer { receiver.stop() }
        do {
            _ = try await receiver.start(accountKey: "legacy:synthetic")
            XCTFail("Unsupported provider must not open a listener")
        } catch { XCTAssertEqual(error as? TokenSpeedError, .invalidAccount) }
    }

    func testRequiresExactAuthenticatedJSONEndpoint() {
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(request(), authorizationHeader: authorization), .ready(Data("{}".utf8)))
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(request(authorization: nil), authorizationHeader: authorization), .rejected(401))
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(request(authorization: "Bearer wrong"), authorizationHeader: authorization), .rejected(401))
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(request(method: "GET"), authorizationHeader: authorization), .rejected(405))
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(request(path: "/other"), authorizationHeader: authorization), .rejected(404))
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(request(extra: "Content-Encoding: gzip\r\n"), authorizationHeader: authorization), .rejected(415))
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(request(path: "/v1/traces"), authorizationHeader: authorization, path: "/v1/traces"), .ready(Data("{}".utf8)))
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(request(path: "/v1/logs"), authorizationHeader: authorization), .rejected(404))
    }

    func testAntigravitySampleRequiresExactEphemeralScopeAndValidMeasurement() throws {
        let now = Date()
        let scope = "antigravity:" + UUID().uuidString
        func data(scopeKey: String? = nil, output: Int = 150, duration: Double = 3000, date: Date? = nil) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["version": 1, "outputTokens": output,
                "durationMilliseconds": duration, "recordedAt": (date ?? now).timeIntervalSince1970,
                "scopeKey": scopeKey ?? scope, "requestKey": "synthetic-hashed-request"])
        }
        let sample = try TokenTelemetrySamplePayload.parse(data(), expectedScope: scope, now: now)
        XCTAssertEqual(sample.tokensPerSecond, 50)
        XCTAssertEqual(sample.accountKey, scope)
        XCTAssertThrowsError(try TokenTelemetrySamplePayload.parse(data(scopeKey: "antigravity:other"), expectedScope: scope, now: now))
        XCTAssertThrowsError(try TokenTelemetrySamplePayload.parse(data(output: -1), expectedScope: scope, now: now))
        XCTAssertThrowsError(try TokenTelemetrySamplePayload.parse(data(duration: 0), expectedScope: scope, now: now))
        XCTAssertThrowsError(try TokenTelemetrySamplePayload.parse(data(date: now.addingTimeInterval(1)), expectedScope: scope, now: now))
        XCTAssertThrowsError(try TokenTelemetrySamplePayload.parse(data(date: now.addingTimeInterval(-901)), expectedScope: scope, now: now))
        XCTAssertThrowsError(try TokenTelemetrySamplePayload.parse(Data(repeating: 32, count: 8193), expectedScope: scope, now: now))
    }

    func testAntigravityReceiverSeparatesEndpointScopeAndRestartState() async throws {
        let received = expectation(description: "Antigravity scoped sample")
        let captured = CapturedSamples()
        let receiver = TokenTelemetryReceiver(provider: .antigravity) { samples in
            captured.append(samples); received.fulfill()
        }
        defer { receiver.stop() }
        let scope = "antigravity:" + UUID().uuidString
        let connection = try await receiver.start(accountKey: scope)
        XCTAssertEqual(connection.endpoint.path, "/v1/samples")
        func send(scopeKey: String, endpoint: URL, credential: String) async throws -> Int? {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: ["version": 1,
                "outputTokens": 200, "durationMilliseconds": 4000,
                "recordedAt": Date().addingTimeInterval(-1).timeIntervalSince1970,
                "scopeKey": scopeKey, "requestKey": "same-request"])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(credential, forHTTPHeaderField: "Authorization")
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode
        }
        let mismatch = try await send(scopeKey: "antigravity:other", endpoint: connection.endpoint, credential: connection.authorizationHeader)
        XCTAssertEqual(mismatch, 400)
        let matching = try await send(scopeKey: scope, endpoint: connection.endpoint, credential: connection.authorizationHeader)
        XCTAssertEqual(matching, 200)
        await fulfillment(of: [received], timeout: 2)
        XCTAssertEqual(captured.values.first?.accountKey, scope)
        receiver.stop()
        let nextScope = "antigravity:" + UUID().uuidString
        let next = try await receiver.start(accountKey: nextScope)
        let previousScope = try await send(scopeKey: scope, endpoint: next.endpoint, credential: next.authorizationHeader)
        XCTAssertEqual(previousScope, 400)
        XCTAssertEqual(captured.values.count, 1)
    }

    func testCodexTraceReceiverJoinsSplitExportsAndClearsTrackerOnRestart() async throws {
        let received = expectation(description: "Codex scoped trace speed")
        let captured = CapturedSamples()
        let receiver = TokenTelemetryReceiver(provider: .codex) { samples in
            captured.append(samples); received.fulfill()
        }
        defer { receiver.stop() }
        let connection = try await receiver.start(accountKey: "codex-profile:synthetic-one")
        XCTAssertEqual(connection.endpoint.path, "/v1/traces")
        let base = Date().addingTimeInterval(-1).timeIntervalSince1970
        func payload(parent: Bool) throws -> Data {
            var span: [String: Any] = ["traceId": String(repeating: "a", count: 32),
                "spanId": String(repeating: parent ? "1" : "2", count: 16),
                "name": parent ? "receiving_stream" : "completed",
                "startTimeUnixNano": String(UInt64((base - (parent ? 12 : 2.01)) * 1_000_000_000)),
                "endTimeUnixNano": String(UInt64((base - (parent ? 0 : 2)) * 1_000_000_000))]
            if !parent {
                span["parentSpanId"] = String(repeating: "1", count: 16)
                span["attributes"] = [["key": "gen_ai.usage.output_tokens", "value": ["intValue": "500"]]]
            }
            return try JSONSerialization.data(withJSONObject: ["resourceSpans": [[
                "resource": ["attributes": [["key": "service.name", "value": ["stringValue": "codex_cli_rs"]]]],
                "scopeSpans": [["spans": [span]]]]]])
        }
        func send(_ data: Data, to connection: TokenTelemetryConnection) async throws -> Int? {
            var request = URLRequest(url: connection.endpoint)
            request.httpMethod = "POST"; request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(connection.authorizationHeader, forHTTPHeaderField: "Authorization")
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode
        }
        let completion = try payload(parent: false), parent = try payload(parent: true)
        let first = try await send(completion, to: connection)
        XCTAssertEqual(first, 200)
        XCTAssertTrue(captured.values.isEmpty)
        let second = try await send(parent, to: connection)
        XCTAssertEqual(second, 200)
        await fulfillment(of: [received], timeout: 2)
        XCTAssertEqual(captured.values.first?.tokensPerSecond ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(captured.values.first?.accountKey, "codex-profile:synthetic-one")
        receiver.stop()
        let next = try await receiver.start(accountKey: "codex-profile:synthetic-two")
        let restarted = try await send(parent, to: next)
        XCTAssertEqual(restarted, 200)
        XCTAssertEqual(captured.values.count, 1)
    }

    func testBoundsFramingAndRejectsAmbiguousHeaders() {
        let complete = request()
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(complete.dropLast(), authorizationHeader: authorization), .incomplete)
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(complete + Data("x".utf8), authorizationHeader: authorization), .rejected(400))
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(request(extra: "Content-Length: 2\r\n"), authorizationHeader: authorization), .rejected(400))
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(request(extra: "Transfer-Encoding: chunked\r\n"), authorizationHeader: authorization), .rejected(400))
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(Data(repeating: 65, count: 16_385), authorizationHeader: authorization), .rejected(431))
        let oversized = request(String(repeating: "x", count: 1_048_577))
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(oversized, authorizationHeader: authorization), .rejected(413))
    }

    func testCodexBatchLimitAllowsFourMiBWhileOtherModeLimitsStayUnchanged() {
        XCTAssertEqual(TokenTelemetryReceiver.maximumBodyBytes(for: .codex), 4 * 1_048_576)
        XCTAssertEqual(TokenTelemetryReceiver.maximumBodyBytes(for: .claude), 0)
        XCTAssertEqual(TokenTelemetryReceiver.maximumBodyBytes(for: .antigravity), 8192)
        let largeCodex = request(String(repeating: "x", count: 2 * 1_048_576), path: "/v1/traces")
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(largeCodex, authorizationHeader: authorization,
            path: "/v1/traces", maximumBodyBytes: TokenTelemetryReceiver.maximumBodyBytes(for: .codex)),
            .ready(Data(repeating: 120, count: 2 * 1_048_576)))
        let excessive = request(String(repeating: "x", count: 4 * 1_048_576 + 1), path: "/v1/traces")
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(excessive, authorizationHeader: authorization,
            path: "/v1/traces", maximumBodyBytes: TokenTelemetryReceiver.maximumBodyBytes(for: .codex)), .rejected(413))
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(request(String(repeating: "x", count: 1_048_577)),
            authorizationHeader: authorization, maximumBodyBytes: TokenTelemetryReceiver.maximumBodyBytes(for: .claude)), .rejected(413))
        XCTAssertEqual(TokenTelemetryHTTPRequest.parse(request(String(repeating: "x", count: 8193), path: "/v1/samples"),
            authorizationHeader: authorization, path: "/v1/samples",
            maximumBodyBytes: TokenTelemetryReceiver.maximumBodyBytes(for: .antigravity)), .rejected(413))
    }

    func testCodexSocketAcceptsBatchLargerThanOneMiB() async throws {
        let receiver = TokenTelemetryReceiver(provider: .codex) { _ in XCTFail("Padding has no measurements") }
        defer { receiver.stop() }
        let connection = try await receiver.start(accountKey: "codex-profile:synthetic-large")
        let body = try JSONSerialization.data(withJSONObject: ["resourceSpans": [],
            "syntheticPadding": String(repeating: "x", count: 2 * 1_048_576)])
        var request = URLRequest(url: connection.endpoint)
        request.httpMethod = "POST"; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(connection.authorizationHeader, forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    func testListenerUsesLoopbackEphemeralPortAndRejectsUnauthenticatedRequest() async throws {
        let receiver = TokenTelemetryReceiver { _ in XCTFail("No telemetry expected") }
        defer { receiver.stop() }
        let account = "codex-profile:synthetic-account"
        let connection = try await receiver.start(accountKey: account)
        XCTAssertEqual(connection.endpoint.host, "127.0.0.1")
        XCTAssertEqual(connection.endpoint.path, "/v1/traces")
        XCTAssertNotNil(connection.endpoint.port)
        var request = URLRequest(url: connection.endpoint)
        request.httpMethod = "POST"; request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 401)
        do { _ = try await receiver.start(accountKey: account); XCTFail("Expected already running") }
        catch { XCTAssertEqual(error as? TokenSpeedError, .alreadyRunning) }
    }

    func testCancelledStartCannotLeaveListenerOrCancelNextStart() async throws {
        let receiver = TokenTelemetryReceiver { _ in XCTFail("No telemetry expected") }
        defer { receiver.stop() }
        let account = "codex-profile:synthetic-account"
        let cancelled = Task { try await receiver.start(accountKey: account) }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Expected cancelled start") }
        catch { XCTAssertTrue(error is CancellationError) }
        let connection = try await receiver.start(accountKey: account)
        XCTAssertEqual(connection.endpoint.host, "127.0.0.1")
    }

    private final class CapturedSamples: @unchecked Sendable {
        private let lock = NSLock()
        private var samples: [TokenSpeedSample] = []
        var values: [TokenSpeedSample] { lock.lock(); defer { lock.unlock() }; return samples }
        func append(_ values: [TokenSpeedSample]) { lock.lock(); samples.append(contentsOf: values); lock.unlock() }
    }
}
