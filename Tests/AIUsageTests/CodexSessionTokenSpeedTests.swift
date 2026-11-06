import XCTest
@testable import AIUsagePlugin

final class CodexSessionTokenSpeedTests: XCTestCase {
    private let session = "055A398F-DB14-4C5F-ABBB-1BF03F8120A7"
    private let other = "155A398F-DB14-4C5F-ABBB-1BF03F8120A7"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func line(_ object: [String: Any]) throws -> Data {
        var result = try JSONSerialization.data(withJSONObject: object)
        result.append(0x0A)
        return result
    }
    private func header(id: String? = nil, mode: String = "paginated") throws -> Data {
        try line(["timestamp": "2027-01-15T08:00:00Z", "type": "session_meta", "payload": [
            "id": id ?? session, "history_mode": mode, "creator_account_id": "PRIVATE_ACCOUNT",
            "base_instructions": ["text": "PRIVATE INSTRUCTIONS"], "cwd": "/PRIVATE/PATH"]])
    }
    private func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    private func turnStarted(_ turn: String = "turn-1", at date: Date? = nil) throws -> Data {
        try line(["timestamp": timestamp(date ?? now.addingTimeInterval(-10)), "type": "event_msg",
            "payload": ["type": "task_started", "turn_id": turn]])
    }
    private func usage(turn: String = "turn-1", response: String = "response-1", thread: String? = nil,
                       output: Any = 500, at date: Date? = nil) throws -> Data {
        try line(["timestamp": timestamp(date ?? now), "type": "token_usage_record", "payload": [
            "thread_id": thread ?? session, "turn_id": turn, "response_id": response,
            "session_id": session, "root_turn_id": turn,
            "turn_token_usage": ["output_tokens": output, "reasoning_output_tokens": 100],
            "usage": ["output_tokens": 17], "thread_token_usage": ["output_tokens": 999_999],
            "content": "PRIVATE RESPONSE"]])
    }
    private func turnComplete(_ turn: String = "turn-1", duration: Any = 10_000,
                              at date: Date? = nil, failed: Bool = false) throws -> Data {
        var payload: [String: Any] = ["type": "task_complete", "turn_id": turn, "duration_ms": duration,
            "last_agent_message": "PRIVATE RESPONSE"]
        if failed { payload["error"] = ["message": "PRIVATE ERROR"] }
        return try line(["timestamp": timestamp(date ?? now), "type": "event_msg", "payload": payload])
    }
    private func item(id: String = "item-1", thread: String? = nil, kind: String = "AgentMessage",
                      tokens: Any = 500, start: Any? = nil, end: Any? = nil) throws -> Data {
        let endValue = end ?? Int64(now.timeIntervalSince1970 * 1000)
        let startValue = start ?? Int64(now.timeIntervalSince1970 * 1000 - 10_000)
        return try line(["type": "event_msg", "payload": ["type": "item_completed",
            "thread_id": thread ?? session, "turn_id": "turn-1", "item": ["type": kind, "id": id,
                "content": [["type": "Text", "text": "PRIVATE RESPONSE"]]],
            "content_token_count": tokens, "started_at_ms": startValue, "completed_at_ms": endValue]])
    }
    private func file(_ data: Data) throws -> URL {
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("happylulu-session-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("selected.jsonl")
        try data.write(to: path)
        return path
    }
    private func append(_ data: Data, to path: URL) throws {
        let handle = try FileHandle(forWritingTo: path)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    func testReadsNativeAssistantMessageTokensAndSameItemTimes() throws {
        let original = try header() + item()
        let path = try file(original)
        var reader = try CodexSessionTokenSpeedReader(path: path.path)
        let sample = try XCTUnwrap(reader.poll(now: now).first)
        XCTAssertEqual(sample.outputTokens, 500)
        XCTAssertEqual(sample.durationMilliseconds, 10_000)
        XCTAssertEqual(sample.tokensPerSecond, 50)
        XCTAssertEqual(sample.recordedAt, now)
        XCTAssertEqual(CodexSessionTokenSpeedReader.metricKind(for: sample), .message)
        XCTAssertTrue(sample.accountKey.hasPrefix("codex-session:"))
        XCTAssertFalse(sample.requestKey.contains("item-1"))
        XCTAssertEqual(try Data(contentsOf: path), original)
        XCTAssertTrue(try reader.poll(now: now).isEmpty)
    }

    func testWaitsForNewlineAndDeduplicatesAppend() throws {
        let complete = try item()
        let split = complete.count / 2
        let path = try file(try header() + complete.prefix(split))
        var reader = try CodexSessionTokenSpeedReader(path: path.path)
        XCTAssertTrue(try reader.poll(now: now).isEmpty)
        try append(Data(complete.dropFirst(split)), to: path)
        XCTAssertEqual(try reader.poll(now: now).count, 1)
        try append(complete, to: path)
        XCTAssertTrue(try reader.poll(now: now).isEmpty)
    }

    func testDoesNotInferFromLegacyOrMissingMetricsOrOtherItems() throws {
        let legacy = try file(header(mode: "legacy"))
        var legacyReader = try CodexSessionTokenSpeedReader(path: legacy.path)
        XCTAssertTrue(try legacyReader.poll(now: now).isEmpty)
        let missing = try line(["type": "event_msg", "payload": ["type": "item_completed", "thread_id": session,
            "turn_id": "turn-1", "item": ["type": "AgentMessage", "id": "missing", "content": "PRIVATE"]]])
        let path = try file(try header() + item(kind: "Reasoning") + missing)
        var reader = try CodexSessionTokenSpeedReader(path: path.path)
        XCTAssertTrue(try reader.poll(now: now).isEmpty)
    }

    func testCodex166ReadsLatestTurnCounterAndCompletionWithoutMessageTokenField() throws {
        let original = try header() + turnStarted() + usage(response: "first", output: 100, at: now.addingTimeInterval(-5)) +
            usage(response: "last", output: 500) + turnComplete()
        let path = try file(original)
        var reader = try CodexSessionTokenSpeedReader(path: path.path)
        let samples = try reader.poll(now: now)
        let sample = try XCTUnwrap(samples.last)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(sample.outputTokens, 500)
        XCTAssertEqual(sample.durationMilliseconds, 10_000)
        XCTAssertEqual(sample.tokensPerSecond, 50)
        XCTAssertEqual(CodexSessionTokenSpeedReader.metricKind(for: sample), .completedTurn)
        XCTAssertEqual(try Data(contentsOf: path), original)
        XCTAssertTrue(try reader.poll(now: now).isEmpty)
    }

    func testTurnMetricsWorkInLegacyAndMissingHistoryMode() throws {
        let absent = try line(["type": "session_meta", "payload": ["id": session]])
        for metadata in [try header(mode: "legacy"), absent] {
            let path = try file(metadata + usage() + turnComplete())
            var reader = try CodexSessionTokenSpeedReader(path: path.path)
            XCTAssertEqual(try reader.poll(now: now).first?.tokensPerSecond, 50)
        }
    }

    func testProgressUsesLastObservationAndIsReplacedByCompletedTurn() throws {
        let path = try file(try header() + turnStarted() + usage(at: now.addingTimeInterval(-5)))
        var reader = try CodexSessionTokenSpeedReader(path: path.path)
        let progress = try XCTUnwrap(reader.poll(now: now).last)
        XCTAssertEqual(progress.tokensPerSecond, 100)
        XCTAssertEqual(progress.recordedAt, now.addingTimeInterval(-5))
        XCTAssertEqual(CodexSessionTokenSpeedReader.metricKind(for: progress), .inProgressTurn)
        XCTAssertTrue(try reader.poll(now: now.addingTimeInterval(1)).isEmpty)
        try append(try usage(response: "last", output: 600) + turnComplete(), to: path)
        let complete = try XCTUnwrap(reader.poll(now: now).last)
        XCTAssertEqual(complete.tokensPerSecond, 60)
        XCTAssertEqual(CodexSessionTokenSpeedReader.metricKind(for: complete), .completedTurn)
    }

    func testOutOfOrderTurnRecordsAndReplayDoNotSumSnapshots() throws {
        let data = try header() + turnComplete() + usage(response: "last", output: 500) +
            usage(response: "first", output: 100, at: now.addingTimeInterval(-5)) + turnStarted() +
            usage(response: "last", output: 500) + turnComplete()
        let path = try file(data)
        var reader = try CodexSessionTokenSpeedReader(path: path.path)
        XCTAssertEqual(try reader.poll(now: now).map(\.outputTokens), [500])
        try append(try usage(response: "first", output: 100, at: now.addingTimeInterval(-5)) + turnComplete(), to: path)
        XCTAssertTrue(try reader.poll(now: now).isEmpty)
    }

    func testCompletionCanJoinAndCorrectLateUsageAcrossPolls() throws {
        let path = try file(try header() + turnComplete())
        var reader = try CodexSessionTokenSpeedReader(path: path.path)
        XCTAssertTrue(try reader.poll(now: now).isEmpty)
        try append(try usage(response: "first", output: 100, at: now.addingTimeInterval(-1)), to: path)
        let first = try XCTUnwrap(reader.poll(now: now).first)
        XCTAssertEqual(first.outputTokens, 100)
        try append(try usage(response: "last", output: 500), to: path)
        let corrected = try XCTUnwrap(reader.poll(now: now).first)
        XCTAssertEqual(corrected.outputTokens, 500)
        XCTAssertEqual(corrected.requestKey, first.requestKey)
        XCTAssertEqual(corrected.recordedAt, first.recordedAt)
        XCTAssertTrue(try reader.poll(now: now).isEmpty)
    }

    func testAbortedAndFailedTurnsInvalidatePreviouslyEmittedProgress() throws {
        let explicitAbort = try line(["type": "event_msg", "payload": ["type": "turn_aborted", "turn_id": "turn-1"]])
        let anonymousAbort = try line(["type": "event_msg", "payload": ["type": "turn_aborted"]])
        for terminal in [explicitAbort, anonymousAbort, try turnComplete(failed: true), try turnComplete(duration: 0)] {
            let path = try file(try header() + turnStarted() + usage(at: now.addingTimeInterval(-5)))
            var reader = try CodexSessionTokenSpeedReader(path: path.path)
            let progress = try XCTUnwrap(reader.poll(now: now).first)
            try append(terminal, to: path)
            XCTAssertTrue(try reader.poll(now: now).isEmpty)
            XCTAssertTrue(reader.invalidatedRequestKeys.contains(progress.requestKey))
            try append(try usage(response: "after-terminal", output: 700), to: path)
            XCTAssertTrue(try reader.poll(now: now).isEmpty)
            XCTAssertTrue(reader.invalidatedRequestKeys.isEmpty)
        }
    }

    func testAbortOnlyInvalidatesItsTurnAndLeavesCompletedTurnIntact() throws {
        let path = try file(try header() + usage(turn: "done") + turnComplete("done") + turnStarted() +
            usage(at: now.addingTimeInterval(-5)))
        var reader = try CodexSessionTokenSpeedReader(path: path.path)
        let samples = try reader.poll(now: now)
        let completed = try XCTUnwrap(samples.first { CodexSessionTokenSpeedReader.metricKind(for: $0) == .completedTurn })
        let progress = try XCTUnwrap(samples.first { CodexSessionTokenSpeedReader.metricKind(for: $0) == .inProgressTurn })
        try append(try line(["type": "event_msg", "payload": ["type": "turn_aborted", "turn_id": "turn-1"]]), to: path)
        XCTAssertTrue(try reader.poll(now: now).isEmpty)
        XCTAssertTrue(reader.invalidatedRequestKeys.contains(progress.requestKey))
        XCTAssertFalse(reader.invalidatedRequestKeys.contains(completed.requestKey))
    }

    func testTurnRecordMustMatchSessionAndCountersCannotRegressOrConflict() throws {
        for records in [
            try usage(thread: other),
            try usage(output: 500, at: now.addingTimeInterval(-2)) + usage(response: "later", output: 100),
            try usage() + usage(output: 501)
        ] {
            let path = try file(try header() + records + turnComplete())
            var reader = try CodexSessionTokenSpeedReader(path: path.path)
            XCTAssertThrowsError(try reader.poll(now: now)) { XCTAssertEqual($0 as? CodexSessionTokenSpeedError, .invalidData) }
        }
    }

    func testTurnFallbackRejectsInvalidDurationsTimesAndMissingUsage() throws {
        var data = try header() + turnComplete("missing")
        data += try usage(turn: "zero", output: 500) + turnComplete("zero", duration: 0)
        data += try usage(turn: "negative", output: -1) + turnComplete("negative")
        data += try usage(turn: "fractional", output: 1.5) + turnComplete("fractional")
        data += try usage(turn: "future", at: now.addingTimeInterval(1)) + turnComplete("future", at: now.addingTimeInterval(1))
        data += try usage(turn: "old", at: now.addingTimeInterval(-910)) + turnComplete("old", at: now.addingTimeInterval(-910))
        data += try usage(turn: "failed") + turnComplete("failed", failed: true)
        let path = try file(data)
        var reader = try CodexSessionTokenSpeedReader(path: path.path)
        XCTAssertTrue(try reader.poll(now: now).isEmpty)
    }

    func testProgressRequiresExplicitValidStartAndPositiveElapsedObservation() throws {
        let malformedStart = try line(["type": "event_msg", "timestamp": "999999999999999999999999999",
            "payload": ["type": "task_started", "turn_id": "turn-1"]])
        let missingStartTime = try line(["type": "event_msg", "payload": ["type": "task_started", "turn_id": "turn-1"]])
        for start in [Data(), malformedStart, missingStartTime, try turnStarted(at: now),
                      try turnStarted(at: now.addingTimeInterval(1))] {
            let path = try file(try header() + start + usage())
            var reader = try CodexSessionTokenSpeedReader(path: path.path)
            XCTAssertTrue(try reader.poll(now: now).isEmpty)
        }
        let zero = try file(try header() + turnStarted() + usage(output: 0))
        var reader = try CodexSessionTokenSpeedReader(path: zero.path)
        XCTAssertTrue(try reader.poll(now: now).isEmpty)
    }

    func testFreshnessBoundaryLargeNumbersAndRotatedTurnsStaySeparate() throws {
        let boundary = now.addingTimeInterval(-900)
        let path = try file(try header() + usage(at: boundary) + turnComplete(at: boundary))
        var reader = try CodexSessionTokenSpeedReader(path: path.path)
        XCTAssertEqual(try reader.poll(now: now).count, 1)
        let oldScope = reader.scopeKey
        let oversized = try usage(output: Int64.max) + turnComplete(duration: Int64.max)
        try (try header() + oversized).write(to: path)
        XCTAssertTrue(try reader.poll(now: now).isEmpty)
        XCTAssertNotEqual(reader.scopeKey, oldScope)
        try (try header() + turnComplete()).write(to: path)
        XCTAssertTrue(try reader.poll(now: now).isEmpty)
    }

    func testRejectsMismatchedSessionAndConflictingItem() throws {
        let path = try file(try header() + item(thread: other))
        var reader = try CodexSessionTokenSpeedReader(path: path.path)
        XCTAssertThrowsError(try reader.poll(now: now)) { XCTAssertEqual($0 as? CodexSessionTokenSpeedError, .invalidData) }
        let repeated = try file(try header() + item() + item(tokens: 501))
        var repeatedReader = try CodexSessionTokenSpeedReader(path: repeated.path)
        XCTAssertThrowsError(try repeatedReader.poll(now: now)) { XCTAssertEqual($0 as? CodexSessionTokenSpeedError, .invalidData) }
    }

    func testRejectsInvalidAndUnobservedTimesWithoutGuessing() throws {
        var data = try header()
        let end = Int64(now.timeIntervalSince1970 * 1000)
        data += try item(id: "negative", tokens: -1)
        data += try item(id: "fraction", tokens: 1.5)
        data += try item(id: "zero-duration", start: end)
        data += try item(id: "future", end: end + 1)
        data += try item(id: "old", start: end - 920_000, end: end - 910_000)
        let path = try file(data)
        var reader = try CodexSessionTokenSpeedReader(path: path.path)
        XCTAssertTrue(try reader.poll(now: now).isEmpty)
    }

    func testRotationAndTruncationResetScopeWithoutJoiningSessions() throws {
        let path = try file(try header() + item())
        var reader = try CodexSessionTokenSpeedReader(path: path.path)
        XCTAssertEqual(try reader.poll(now: now).count, 1)
        let firstScope = reader.scopeKey
        try header().write(to: path)
        XCTAssertTrue(try reader.poll(now: now).isEmpty)
        XCTAssertNotEqual(reader.scopeKey, firstScope)
        let secondScope = reader.scopeKey
        let replacement = path.deletingLastPathComponent().appendingPathComponent("replacement.jsonl")
        try (try header(id: other) + item(thread: other)).write(to: replacement)
        _ = try FileManager.default.replaceItemAt(path, withItemAt: replacement)
        XCTAssertEqual(try reader.poll(now: now).count, 1)
        XCTAssertNotEqual(reader.scopeKey, secondScope)
    }

    func testRejectsSymlinkDirectoryAndTooLargeFile() throws {
        XCTAssertThrowsError(try CodexSessionTokenSpeedReader(path: "relative.jsonl"))
        let path = try file(try header())
        let link = path.deletingLastPathComponent().appendingPathComponent("link.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: path)
        var linked = try CodexSessionTokenSpeedReader(path: link.path)
        XCTAssertThrowsError(try linked.poll(now: now))
        let parentLink = path.deletingLastPathComponent().appendingPathComponent("linked-parent")
        try FileManager.default.createSymbolicLink(at: parentLink, withDestinationURL: path.deletingLastPathComponent())
        var linkedParent = try CodexSessionTokenSpeedReader(path: parentLink.appendingPathComponent("selected.jsonl").path)
        XCTAssertThrowsError(try linkedParent.poll(now: now))
        var directory = try CodexSessionTokenSpeedReader(path: path.deletingLastPathComponent().path)
        XCTAssertThrowsError(try directory.poll(now: now))
        let handle = try FileHandle(forWritingTo: path)
        try handle.truncate(atOffset: 67_108_865)
        try handle.close()
        var oversized = try CodexSessionTokenSpeedReader(path: path.path)
        XCTAssertThrowsError(try oversized.poll(now: now)) { XCTAssertEqual($0 as? CodexSessionTokenSpeedError, .fileTooLarge) }
    }

    func testBoundedPollingSkipsOversizedContentLineAndRecovers() throws {
        let path = try file(try header() + Data(repeating: 0x20, count: 1_048_577) + Data([0x0A]) + item())
        var reader = try CodexSessionTokenSpeedReader(path: path.path)
        XCTAssertTrue(try reader.poll(now: now).isEmpty)
        XCTAssertTrue(reader.hasMoreData)
        let samples = try reader.poll(now: now)
        XCTAssertEqual(samples.count, 1)
        XCTAssertFalse(reader.hasMoreData)
    }
}
