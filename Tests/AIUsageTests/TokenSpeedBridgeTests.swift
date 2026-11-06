import XCTest
@testable import AIUsagePlugin

final class TokenSpeedBridgeTests: XCTestCase {
    private let scope = "antigravity:11111111-1111-1111-1111-111111111111"
    private let conversation = "22222222-2222-2222-2222-222222222222"

    func testForwardsEveryByteAndDeliversOnlySanitizedMetrics() async throws {
        let input = "{\"event\":\"init\",\"conversation_id\":\"\(conversation)\"}\r\n" +
            "not JSON\n" + step(text: "private response") + "\n"
        let samples = BridgeSamples()
        let output = try await forward(Data(input.utf8), samples: samples)
        XCTAssertEqual(output, Data(input.utf8))
        XCTAssertEqual(samples.values.count, 1)
        let sample = try XCTUnwrap(samples.values.first)
        XCTAssertEqual(sample.tokensPerSecond, 50)
        let body = try TokenSpeedBridge.samplePayload(sample)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "outputTokens", "durationMilliseconds", "recordedAt", "scopeKey", "requestKey"])
        XCTAssertEqual(object["scopeKey"] as? String, scope)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("private response"))
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(conversation))
    }

    func testOversizedLineDoesNotStopOutputOrFollowingMeasurements() async throws {
        var input = Data(repeating: 0x78, count: 1_048_577)
        input.append(Data(("\n{\"event\":\"init\",\"conversation_id\":\"\(conversation)\"}\n" + step(text: "") ).utf8))
        let samples = BridgeSamples()
        let output = try await forward(input, samples: samples)
        XCTAssertEqual(output, input)
        XCTAssertEqual(samples.values.count, 1)
    }

    func testConfigurationRejectsRemoteURLsAndHeaderInjection() throws {
        let valid = ["HAPPY_LULU_TOKEN_ENDPOINT": "http://127.0.0.1:12345/v1/samples",
                     "HAPPY_LULU_TOKEN_AUTH": "Bearer abc-123", "HAPPY_LULU_TOKEN_SCOPE": scope]
        XCTAssertNoThrow(try TokenSpeedBridge.Configuration(environment: valid))
        for endpoint in ["https://127.0.0.1:12345/v1/samples", "http://localhost:12345/v1/samples",
                         "http://example.com:12345/v1/samples", "http://127.0.0.1:12345/v1/samples?q=1",
                         "http://user@127.0.0.1:12345/v1/samples", "http://127.0.0.1:12345/v1/logs"] {
            var environment = valid; environment["HAPPY_LULU_TOKEN_ENDPOINT"] = endpoint
            XCTAssertThrowsError(try TokenSpeedBridge.Configuration(environment: environment))
        }
        var bad = valid; bad["HAPPY_LULU_TOKEN_AUTH"] = "Bearer abc\r\nX: secret"
        XCTAssertThrowsError(try TokenSpeedBridge.Configuration(environment: bad))
        bad = valid; bad["HAPPY_LULU_TOKEN_SCOPE"] = "antigravity:not-a-uuid"
        XCTAssertThrowsError(try TokenSpeedBridge.Configuration(environment: bad))
    }

    func testMissingConfigurationStillPreservesCLIOutput() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source")
        let destination = directory.appendingPathComponent("destination")
        let bytes = Data("response without metrics\n".utf8)
        try bytes.write(to: source); _ = FileManager.default.createFile(atPath: destination.path, contents: nil)
        let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: destination)
        defer { try? input.close(); try? output.close() }
        let result = await TokenSpeedBridge.run(provider: "antigravity", environment: [:], input: input, output: output)
        XCTAssertEqual(result, 0)
        try output.synchronize()
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
    }

    func testBridgeReachesAuthenticatedLoopbackReceiver() async throws {
        let samples = BridgeSamples()
        let receiver = TokenTelemetryReceiver(provider: .antigravity) { values in
            for value in values { samples.append(value) }
        }
        let connection = try await receiver.start(accountKey: scope)
        defer { receiver.stop() }
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source"), destination = directory.appendingPathComponent("destination")
        let bytes = Data(("{\"event\":\"init\",\"conversation_id\":\"\(conversation)\"}\n" + step(text: "private response") + "\n").utf8)
        try bytes.write(to: source); _ = FileManager.default.createFile(atPath: destination.path, contents: nil)
        let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: destination)
        defer { try? input.close(); try? output.close() }
        let result = await TokenSpeedBridge.run(provider: "antigravity", environment: [
            "HAPPY_LULU_TOKEN_ENDPOINT": connection.endpoint.absoluteString,
            "HAPPY_LULU_TOKEN_AUTH": connection.authorizationHeader, "HAPPY_LULU_TOKEN_SCOPE": scope
        ], input: input, output: output)
        XCTAssertEqual(result, 0)
        XCTAssertEqual(samples.values.count, 1)
        XCTAssertEqual(samples.values.first?.tokensPerSecond, 50)
        try output.synchronize()
        XCTAssertEqual(try Data(contentsOf: destination), bytes)
    }

    private func step(text: String) -> String {
        "{\"event\":\"step_update\",\"step_update\":{\"conversation_id\":\"\(conversation)\",\"step_index\":1,\"state\":\"DONE\",\"step_type\":\"agent_response\",\"duration_seconds\":2,\"usage\":{\"output_tokens\":100},\"text_delta\":\"\(text)\"}}"
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("HappyLulu-bridge-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func forward(_ bytes: Data, samples: BridgeSamples) async throws -> Data {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source"), destination = directory.appendingPathComponent("destination")
        try bytes.write(to: source); _ = FileManager.default.createFile(atPath: destination.path, contents: nil)
        let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: destination)
        defer { try? input.close(); try? output.close() }
        try await TokenSpeedBridge.forward(input: input, output: output, scopeKey: scope) { samples.append($0) }
        try output.synchronize()
        return try Data(contentsOf: destination)
    }
}

private final class BridgeSamples: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [TokenSpeedSample] = []
    var values: [TokenSpeedSample] { lock.lock(); defer { lock.unlock() }; return samples }
    func append(_ sample: TokenSpeedSample) { lock.lock(); samples.append(sample); lock.unlock() }
}
