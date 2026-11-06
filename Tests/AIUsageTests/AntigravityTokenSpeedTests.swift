import XCTest
@testable import AIUsagePlugin

final class AntigravityTokenSpeedTests: XCTestCase {
    private let conversation = "055A398F-DB14-4C5F-ABBB-1BF03F8120A7"
    private let otherConversation = "155A398F-DB14-4C5F-ABBB-1BF03F8120A7"
    private let time = Date(timeIntervalSince1970: 1_800_000_000)

    private func line(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }
    private func start(_ id: String? = nil) throws -> Data {
        try line(["event": "init", "conversation_id": id ?? conversation, "init": ["cwd": "/private", "tools": []]])
    }
    private func step(index: Int = 3, id: String? = nil, state: String = "DONE", type: String = "agent_response",
                      tokens: Any = 582, duration: Any = 6.0) throws -> Data {
        try line(["event": "step_update", "step_update": ["conversation_id": id ?? conversation,
            "step_index": index, "state": state, "step_type": type, "duration_seconds": duration,
            "usage": ["output_tokens": tokens], "text_delta": "PRIVATE RESPONSE MUST NOT BE RETAINED"]])
    }

    func testUsesSameCompletedAgentStepTokensAndDuration() throws {
        var stream = try AntigravityTokenSpeedStream(scopeKey: "antigravity:test")
        XCTAssertNil(try stream.consume(line: start(), receivedAt: time))
        let sample = try XCTUnwrap(stream.consume(line: step(), receivedAt: time))
        XCTAssertEqual(sample.outputTokens, 582)
        XCTAssertEqual(sample.durationMilliseconds, 6000)
        XCTAssertEqual(sample.tokensPerSecond, 97)
        XCTAssertEqual(sample.recordedAt, time)
        XCTAssertEqual(sample.accountKey, "antigravity:test")
        XCTAssertEqual(sample.requestKey.count, 64)
        XCTAssertFalse(sample.requestKey.contains(conversation))
    }

    func testIgnoresPartialToolCheckpointAndCumulativeResult() throws {
        var stream = try AntigravityTokenSpeedStream(scopeKey: "antigravity:test")
        _ = try stream.consume(line: start(), receivedAt: time)
        for (state, type) in [("ACTIVE", "agent_response"), ("DONE", "tool"), ("DONE", "checkpoint")] {
            XCTAssertNil(try stream.consume(line: step(state: state, type: type), receivedAt: time))
        }
        XCTAssertNil(try stream.consume(line: line(["event": "result", "result": ["status": "SUCCESS",
            "usage": ["output_tokens": 99999], "duration_seconds": 1]]), receivedAt: time))
        XCTAssertNil(try stream.consume(line: line(["event": "future_event"]), receivedAt: time))
    }

    func testRequiresInitializedMatchingConversation() throws {
        var stream = try AntigravityTokenSpeedStream(scopeKey: "antigravity:test")
        XCTAssertThrowsError(try stream.consume(line: step(), receivedAt: time))
        _ = try stream.consume(line: start(), receivedAt: time)
        XCTAssertThrowsError(try stream.consume(line: step(id: otherConversation), receivedAt: time))
        XCTAssertThrowsError(try stream.consume(line: start(otherConversation), receivedAt: time))
        XCTAssertNil(try stream.consume(line: start(), receivedAt: time))
    }

    func testDeduplicatesEachStepAndKeepsSeparateStepRequests() throws {
        var stream = try AntigravityTokenSpeedStream(scopeKey: "antigravity:test")
        _ = try stream.consume(line: start(), receivedAt: time)
        let first = try XCTUnwrap(stream.consume(line: step(index: 3), receivedAt: time))
        XCTAssertNil(try stream.consume(line: step(index: 3), receivedAt: time.addingTimeInterval(1)))
        let second = try XCTUnwrap(stream.consume(line: step(index: 7), receivedAt: time))
        XCTAssertNotEqual(first.requestKey, second.requestKey)
        XCTAssertThrowsError(try stream.consume(line: step(index: 3, tokens: 583), receivedAt: time))
    }

    func testRejectsMalformedMetricsAndInvalidScope() throws {
        XCTAssertThrowsError(try AntigravityTokenSpeedStream(scopeKey: "unsupported:wrong"))
        var stream = try AntigravityTokenSpeedStream(scopeKey: "antigravity:test")
        _ = try stream.consume(line: start(), receivedAt: time)
        for tokens in [-1, 100_000_001, 1.5] as [Any] {
            XCTAssertThrowsError(try stream.consume(line: step(tokens: tokens), receivedAt: time))
        }
        for duration in [0, -1, 3601] {
            XCTAssertThrowsError(try stream.consume(line: step(duration: duration), receivedAt: time))
        }
        XCTAssertThrowsError(try stream.consume(line: step(index: -1), receivedAt: time))
        XCTAssertThrowsError(try stream.consume(line: Data("not-json".utf8), receivedAt: time))
        XCTAssertThrowsError(try stream.consume(line: Data(repeating: 0x20, count: 1_048_577), receivedAt: time))
    }

    func testMissingStepMetricsDoesNotInventSpeed() throws {
        var stream = try AntigravityTokenSpeedStream(scopeKey: "antigravity:test")
        _ = try stream.consume(line: start(), receivedAt: time)
        XCTAssertNil(try stream.consume(line: line(["event": "step_update", "step_update": [
            "conversation_id": conversation, "step_index": 2, "state": "DONE", "step_type": "agent_response"]]), receivedAt: time))
        let sample = try XCTUnwrap(stream.consume(line: step(index: 2, tokens: 0), receivedAt: time))
        XCTAssertEqual(sample.tokensPerSecond, 0)
    }

    func testCompletedStepMemoryIsBoundedWithoutForgettingDuplicates() throws {
        var stream = try AntigravityTokenSpeedStream(scopeKey: "antigravity:test")
        _ = try stream.consume(line: start(), receivedAt: time)
        for index in 0..<4096 {
            XCTAssertNotNil(try stream.consume(line: step(index: index), receivedAt: time))
        }
        XCTAssertNil(try stream.consume(line: step(index: 0), receivedAt: time))
        XCTAssertThrowsError(try stream.consume(line: step(index: 4096), receivedAt: time))
    }
}
