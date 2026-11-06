import XCTest
@testable import AIUsagePlugin

final class CodexTokenSpeedTests: XCTestCase {
    private let account = "codex-test-account"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let trace = String(repeating: "a", count: 32)
    private let parent = String(repeating: "1", count: 16)
    private let child = String(repeating: "2", count: 16)

    private func span(_ id: String, parent: String? = nil, name: String,
                      start: Double = 10, end: Double = 0, tokens: Int? = nil,
                      traceID: String? = nil, error: Bool = false) -> [String: Any] {
        var value: [String: Any] = ["traceId": traceID ?? trace, "spanId": id, "name": name,
            "startTimeUnixNano": String(UInt64((now.timeIntervalSince1970 - start) * 1_000_000_000)),
            "endTimeUnixNano": String(UInt64((now.timeIntervalSince1970 - end) * 1_000_000_000))]
        if let parent { value["parentSpanId"] = parent }
        if let tokens { value["attributes"] = [["key": "gen_ai.usage.output_tokens", "value": ["intValue": String(tokens)]]] }
        if error { value["status"] = ["code": 2] }
        return value
    }
    private func payload(_ spans: [[String: Any]], service: String = "codex_cli_rs") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["resourceSpans": [[
            "resource": ["attributes": [["key": "service.name", "value": ["stringValue": service]]]],
            "scopeSpans": [["spans": spans]]]]])
    }

    func testUsesReceivingStartAndCompletedEndInsteadOfTinyEventOrLongToolTail() throws {
        var tracker = try CodexTokenSpeedTracker(accountKey: account)
        let result = try tracker.ingestOTLP(data: payload([
            span(parent, name: "receiving_stream", start: 12, end: 0),
            span(child, parent: parent, name: "completed", start: 2.01, end: 2, tokens: 500)
        ]), now: now)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.outputTokens, 500)
        XCTAssertEqual(result.first?.durationMilliseconds ?? 0, 10_000, accuracy: 0.001)
        XCTAssertEqual(result.first?.tokensPerSecond ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(result.first?.recordedAt, now.addingTimeInterval(-2))
        XCTAssertEqual(result.first?.accountKey, account)
    }

    func testJoinsSplitOutOfOrderBatchesOnceAndSeparatesTraceIDs() throws {
        var tracker = try CodexTokenSpeedTracker(accountKey: account)
        let completion = try payload([span(child, parent: parent, name: "completed", end: 1, tokens: 100)])
        XCTAssertTrue(try tracker.ingestOTLP(data: completion, now: now).isEmpty)
        XCTAssertTrue(try tracker.ingestOTLP(data: payload([span(parent, name: "receiving_stream", traceID: String(repeating: "b", count: 32))]), now: now).isEmpty)
        let matching = try payload([span(parent, name: "receiving_stream")])
        XCTAssertEqual(try tracker.ingestOTLP(data: matching, now: now).count, 1)
        XCTAssertTrue(try tracker.ingestOTLP(data: completion, now: now).isEmpty)
        XCTAssertTrue(try tracker.ingestOTLP(data: matching, now: now).isEmpty)
    }

    func testWrongParentErrorsAndUnavailableUsageNeverProduceSpeed() throws {
        for spans in [
            [span(parent, name: "sampling"), span(child, parent: parent, name: "completed", tokens: 100)],
            [span(parent, name: "receiving_stream", error: true), span(child, parent: parent, name: "completed", tokens: 100)],
            [span(parent, name: "receiving_stream"), span(child, parent: parent, name: "completed", tokens: -1)],
            [span(parent, name: "receiving_stream"), span(child, parent: parent, name: "completed")],
            [span(parent, name: "receiving_stream"), span(child, parent: parent, name: "text_delta", tokens: 100)]
        ] {
            var tracker = try CodexTokenSpeedTracker(accountKey: account)
            XCTAssertTrue(try tracker.ingestOTLP(data: payload(spans), now: now).isEmpty)
        }
    }

    func testStaleFutureAndInvalidRelationshipsNeverProduceSpeed() throws {
        for spans in [
            [span(parent, name: "receiving_stream", start: 1000, end: 950), span(child, parent: parent, name: "completed", start: 960, end: 955, tokens: 100)],
            [span(parent, name: "receiving_stream", start: 10, end: -1), span(child, parent: parent, name: "completed", start: 2, end: 1, tokens: 100)],
            [span(parent, name: "receiving_stream", start: 10, end: 3), span(child, parent: parent, name: "completed", start: 2, end: 1, tokens: 100)],
            [span(parent, name: "receiving_stream", start: 5), span(child, parent: parent, name: "completed", start: 10, end: 1, tokens: 100)]
        ] {
            var tracker = try CodexTokenSpeedTracker(accountKey: account)
            XCTAssertTrue(try tracker.ingestOTLP(data: payload(spans), now: now).isEmpty)
        }
    }

    func testConflictingSpanAndMultipleCompletionsAreRejected() throws {
        var tracker = try CodexTokenSpeedTracker(accountKey: account)
        XCTAssertThrowsError(try tracker.ingestOTLP(data: payload([
            span(parent, name: "receiving_stream"),
            span(child, parent: parent, name: "completed", tokens: 100),
            span(child, parent: parent, name: "completed", tokens: 200)
        ]), now: now))
        tracker = try CodexTokenSpeedTracker(accountKey: account)
        XCTAssertThrowsError(try tracker.ingestOTLP(data: payload([
            span(parent, name: "receiving_stream"),
            span(child, parent: parent, name: "completed", tokens: 100),
            span(String(repeating: "3", count: 16), parent: parent, name: "completed", tokens: 200)
        ]), now: now))
    }

    func testIgnoresNonCodexServiceAndDoesNotDecodeContentFields() throws {
        var tracker = try CodexTokenSpeedTracker(accountKey: account)
        let spans = [span(parent, name: "receiving_stream"), span(child, parent: parent, name: "completed", tokens: 0)]
        XCTAssertTrue(try tracker.ingestOTLP(data: payload(spans, service: "another-app"), now: now).isEmpty)
        var completion = spans[1]
        completion["events"] = [["name": "private text", "attributes": [["value": ["arrayValue": ["ignored"]]]]]]
        XCTAssertEqual(try tracker.ingestOTLP(data: payload([spans[0], completion]), now: now).first?.outputTokens, 0)
    }

    func testPayloadIdentityAndSizeLimits() throws {
        XCTAssertThrowsError(try CodexTokenSpeedTracker(accountKey: ""))
        var tracker = try CodexTokenSpeedTracker(accountKey: account)
        XCTAssertThrowsError(try tracker.ingestOTLP(data: Data(repeating: 32, count: 4_194_305), now: now))
        XCTAssertThrowsError(try tracker.ingestOTLP(data: Data("{}".utf8), now: now))
        var invalid = span(child, parent: parent, name: "completed", tokens: 100)
        invalid["traceId"] = "invalid"
        XCTAssertThrowsError(try tracker.ingestOTLP(data: payload([invalid]), now: now))
    }

    func testAcceptsBoundedCodexBatchAboveOneMiBWithoutMaterializingOtherSpanContent() throws {
        var tracker = try CodexTokenSpeedTracker(accountKey: account)
        var stream = span(parent, name: "receiving_stream")
        stream["events"] = [["name": String(repeating: "x", count: 1_100_000)]]
        let data = try payload([stream, span(child, parent: parent, name: "completed", tokens: 100)])
        XCTAssertGreaterThan(data.count, 1_048_576)
        XCTAssertEqual(try tracker.ingestOTLP(data: data, now: now).count, 1)
    }

    func testDesktopOriginatorAndUnrenamedCompletionMatchObservedCodex166Shape() throws {
        var tracker = try CodexTokenSpeedTracker(accountKey: account)
        let data = try payload([
            span(parent, name: "receiving_stream"),
            span(String(repeating: "4", count: 16), parent: parent, name: "handle_responses", start: 9, end: 8),
            span(child, parent: parent, name: "handle_responses", start: 1.01, end: 1, tokens: 450)
        ], service: "Codex Desktop")
        let result = try tracker.ingestOTLP(data: data, now: now)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.tokensPerSecond ?? 0, 50, accuracy: 0.001)
        XCTAssertTrue(try tracker.ingestOTLP(data: data, now: now).isEmpty)
    }

    func testDifferentCompletionNamesCannotDoubleCountOneReceivingStream() throws {
        var tracker = try CodexTokenSpeedTracker(accountKey: account)
        XCTAssertThrowsError(try tracker.ingestOTLP(data: payload([
            span(parent, name: "receiving_stream"),
            span(child, parent: parent, name: "completed", tokens: 100),
            span(String(repeating: "3", count: 16), parent: parent, name: "handle_responses", tokens: 100)
        ]), now: now))
    }
}
