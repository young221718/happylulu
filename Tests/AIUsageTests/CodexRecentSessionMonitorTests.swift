import XCTest
@testable import AIUsagePlugin

final class CodexRecentSessionMonitorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_923_200)
    private let sessionID = "00000000-0000-0000-0000-000000000001"

    private func temporaryHome() throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("happylulu-recent-codex-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func rollout(_ root: URL, day: String = "2026-11-06", number: Int = 1,
                         tokens: Int = 200, age: TimeInterval = 10) throws -> URL {
        let parts = day.split(separator: "-").map(String.init)
        let directory = root.appendingPathComponent("sessions/" + parts.joined(separator: "/"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = String(format: "00000000-0000-0000-0000-%012d", number)
        let path = directory.appendingPathComponent("rollout-\(day)T12-00-00-\(id).jsonl")
        let end = Int64(now.addingTimeInterval(-age).timeIntervalSince1970 * 1000)
        let records: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": sessionID, "history_mode": "paginated"]],
            ["type": "event_msg", "payload": ["type": "item_completed", "thread_id": sessionID,
                "turn_id": "turn-\(number)", "item": ["type": "AgentMessage", "id": "item-\(number)", "content": "PRIVATE_CONTENT_NEVER_RETURNED"],
                "content_token_count": tokens, "started_at_ms": end - 10_000, "completed_at_ms": end]]
        ]
        let data = try records.reduce(into: Data()) { result, record in
            result.append(try JSONSerialization.data(withJSONObject: record)); result.append(0x0A)
        }
        try data.write(to: path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: path.path)
        return path
    }

    func testFindsRecentStandardRolloutAndUsesAnonymousMonitorScope() async throws {
        let root = try temporaryHome()
        _ = try rollout(root)
        let monitor = try CodexRecentSessionMonitor(codexHome: root.path)
        let value = try await monitor.poll(now: now)
        XCTAssertEqual(value.discoveredSessionCount, 1)
        XCTAssertEqual(value.latestSample?.tokensPerSecond, 20)
        XCTAssertEqual(value.latestSample?.accountKey, monitor.scopeKey)
        XCTAssertTrue(monitor.scopeKey.hasPrefix("codex-recent:"))
        XCTAssertEqual(value.latestSample.flatMap(CodexSessionTokenSpeedReader.metricKind(for:)), .message)
        XCTAssertFalse(value.isCatchingUp)
    }

    func testKeepsLatestSampleAcrossFilesAndDoesNotJoinTheirCounters() async throws {
        let root = try temporaryHome()
        _ = try rollout(root, number: 1, tokens: 400, age: 100)
        _ = try rollout(root, number: 2, tokens: 120, age: 2)
        let monitor = try CodexRecentSessionMonitor(codexHome: root.path)
        let value = try await monitor.poll(now: now)
        XCTAssertEqual(value.latestSample?.tokensPerSecond, 12)
        XCTAssertEqual(value.discoveredSessionCount, 2)
        let repeated = try await monitor.poll(now: now)
        XCTAssertEqual(repeated.latestSample, value.latestSample)
    }

    func testIgnoresUnexpectedNamesOldAndFutureFiles() async throws {
        let root = try temporaryHome()
        let valid = try rollout(root)
        let unexpected = valid.deletingLastPathComponent().appendingPathComponent("credentials.jsonl")
        try Data("DO_NOT_READ".utf8).write(to: unexpected)
        _ = try rollout(root, number: 2, age: 901)
        _ = try rollout(root, number: 3, age: -60)
        _ = try rollout(root, day: "2026-09-01", number: 4)
        let monitor = try CodexRecentSessionMonitor(codexHome: root.path)
        let value = try await monitor.poll(now: now)
        XCTAssertEqual(value.discoveredSessionCount, 1)
        XCTAssertEqual(value.unsupportedSessionCount, 0)
    }

    func testRejectsSymlinkHomeAndIgnoresSymlinkDatesAndFiles() async throws {
        let root = try temporaryHome()
        let real = try temporaryHome()
        _ = try rollout(real)
        let link = root.appendingPathComponent("linked-home")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let linked = try CodexRecentSessionMonitor(codexHome: link.path)
        do { _ = try await linked.poll(now: now); XCTFail("Symlink root was read") }
        catch { XCTAssertEqual(error as? CodexRecentSessionMonitorError, .unsafeDirectory) }
        let dateDirectory = root.appendingPathComponent("sessions/2026/11")
        try FileManager.default.createDirectory(at: dateDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dateDirectory.appendingPathComponent("06"),
            withDestinationURL: real.appendingPathComponent("sessions/2026/11/06"))
        let monitor = try CodexRecentSessionMonitor(codexHome: root.path)
        let value = try await monitor.poll(now: now)
        XCTAssertEqual(value.discoveredSessionCount, 0)

        let leafHome = try temporaryHome()
        let leaf = try rollout(leafHome)
        try FileManager.default.removeItem(at: leaf)
        let target = try rollout(real)
        try FileManager.default.createSymbolicLink(at: leaf, withDestinationURL: target)
        let leafMonitor = try CodexRecentSessionMonitor(codexHome: leafHome.path)
        let leafValue = try await leafMonitor.poll(now: now)
        XCTAssertEqual(leafValue.discoveredSessionCount, 0)
        XCTAssertNil(leafValue.latestSample)
    }

    func testOneUnsupportedFileDoesNotHideAnotherValidSession() async throws {
        let root = try temporaryHome()
        _ = try rollout(root, number: 1)
        let bad = try rollout(root, number: 2, age: 1)
        try Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"invalid-session\"}}\n".utf8).write(to: bad)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-1)], ofItemAtPath: bad.path)
        let monitor = try CodexRecentSessionMonitor(codexHome: root.path)
        let value = try await monitor.poll(now: now)
        XCTAssertEqual(value.latestSample?.tokensPerSecond, 20)
        XCTAssertEqual(value.unsupportedSessionCount, 1)
    }

    func testCapsCandidateCountAndDiscardsExpiredSamples() async throws {
        let root = try temporaryHome()
        for number in 1...12 { _ = try rollout(root, number: number, age: Double(number)) }
        let monitor = try CodexRecentSessionMonitor(codexHome: root.path)
        var value = try await monitor.poll(now: now)
        XCTAssertEqual(value.discoveredSessionCount, 8)
        if value.isCatchingUp { value = try await monitor.poll(now: now) }
        XCTAssertNotNil(value.latestSample)
        let stale = try await monitor.poll(now: now.addingTimeInterval(901))
        XCTAssertNil(stale.latestSample)
        XCTAssertEqual(stale.discoveredSessionCount, 0)
    }

    func testCatchesUpIncrementallyWithoutReturningUnrelatedContent() async throws {
        let root = try temporaryHome()
        let path = try rollout(root)
        let lines = try Data(contentsOf: path).split(separator: 0x0A)
        let ignored = try JSONSerialization.data(withJSONObject: ["type": "turn_context",
            "payload": ["content": String(repeating: "PRIVATE_CONTENT_NEVER_RETURNED", count: 20_000)]])
        var data = Data(lines[0]); data.append(0x0A)
        for _ in 0..<4 { data.append(ignored); data.append(0x0A) }
        data.append(contentsOf: lines[1]); data.append(0x0A)
        try data.write(to: path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10)], ofItemAtPath: path.path)
        let monitor = try CodexRecentSessionMonitor(codexHome: root.path)
        var value = try await monitor.poll(now: now)
        XCTAssertTrue(value.isCatchingUp)
        XCTAssertNil(value.latestSample)
        for _ in 0..<4 where value.isCatchingUp { value = try await monitor.poll(now: now) }
        XCTAssertFalse(value.isCatchingUp)
        XCTAssertEqual(value.latestSample?.tokensPerSecond, 20)
        XCTAssertEqual(value.unsupportedSessionCount, 0)
    }

    func testReplacesCompletedTurnSampleWhenLateCounterCorrectsSameRequest() async throws {
        let root = try temporaryHome()
        let path = try rollout(root)
        let formatter = ISO8601DateFormatter()
        func line(_ record: [String: Any]) throws -> Data {
            var result = try JSONSerialization.data(withJSONObject: record); result.append(0x0A)
            return result
        }
        func usage(_ tokens: Int, response: String, age: TimeInterval) throws -> Data {
            try line(["timestamp": formatter.string(from: now.addingTimeInterval(-age)), "type": "token_usage_record",
                "payload": ["thread_id": sessionID, "turn_id": "turn", "response_id": response,
                    "turn_token_usage": ["output_tokens": tokens]]])
        }
        var data = try line(["type": "session_meta", "payload": ["id": sessionID]])
        data.append(try usage(200, response: "first", age: 20))
        data.append(try line(["timestamp": formatter.string(from: now.addingTimeInterval(-10)), "type": "event_msg",
            "payload": ["type": "task_complete", "turn_id": "turn", "duration_ms": 10_000]]))
        try data.write(to: path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10)], ofItemAtPath: path.path)
        let monitor = try CodexRecentSessionMonitor(codexHome: root.path)
        let original = try await monitor.poll(now: now)
        XCTAssertEqual(original.latestSample?.tokensPerSecond, 20)
        data.append(try usage(300, response: "late", age: 15))
        try data.write(to: path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-5)], ofItemAtPath: path.path)
        let corrected = try await monitor.poll(now: now)
        XCTAssertEqual(corrected.latestSample?.tokensPerSecond, 30)
        XCTAssertEqual(corrected.latestSample?.requestKey, original.latestSample?.requestKey)
        XCTAssertEqual(corrected.latestSample?.recordedAt, original.latestSample?.recordedAt)
    }

    func testInvalidPathAndCancelledPollDoNotRead() async throws {
        XCTAssertThrowsError(try CodexRecentSessionMonitor(codexHome: "relative/path"))
        XCTAssertThrowsError(try CodexRecentSessionMonitor(codexHome: "/private/tmp/../outside"))
        let root = try temporaryHome()
        let monitor = try CodexRecentSessionMonitor(codexHome: root.path)
        let date = now
        let work = Task { () throws -> CodexRecentSessionObservation in
            try Task.checkCancellation()
            return try await monitor.poll(now: date)
        }
        work.cancel()
        do { _ = try await work.value; XCTFail("Cancelled poll completed") }
        catch is CancellationError {}
    }

    func testAbortClearsPreviouslyObservedProgress() async throws {
        try await verifyProgressInvalidation(failedCompletion: false)
    }

    func testFailedCompletionClearsPreviouslyObservedProgress() async throws {
        try await verifyProgressInvalidation(failedCompletion: true)
    }

    func testAbortKeepsValidOtherSampleReturnedInSamePoll() async throws {
        try await verifyProgressInvalidation(failedCompletion: false, replaceWithValid: true)
    }

    private func verifyProgressInvalidation(failedCompletion: Bool, replaceWithValid: Bool = false) async throws {
        let root = try temporaryHome()
        let path = try rollout(root)
        let formatter = ISO8601DateFormatter()
        func line(_ record: [String: Any]) throws -> Data {
            var result = try JSONSerialization.data(withJSONObject: record); result.append(0x0A)
            return result
        }
        var data = try line(["type": "session_meta", "payload": ["id": sessionID]])
        data.append(try line(["timestamp": formatter.string(from: now.addingTimeInterval(-20)), "type": "event_msg",
            "payload": ["type": "task_started", "turn_id": "interrupted"]]))
        data.append(try line(["timestamp": formatter.string(from: now.addingTimeInterval(-10)), "type": "token_usage_record",
            "payload": ["thread_id": sessionID, "turn_id": "interrupted", "response_id": "first",
                "turn_token_usage": ["output_tokens": 200]]]))
        try data.write(to: path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10)], ofItemAtPath: path.path)
        let monitor = try CodexRecentSessionMonitor(codexHome: root.path)
        let progress = try await monitor.poll(now: now)
        XCTAssertEqual(progress.latestSample?.tokensPerSecond, 20)
        XCTAssertEqual(progress.latestSample.flatMap(CodexSessionTokenSpeedReader.metricKind(for:)), .inProgressTurn)
        let terminal: [String: Any] = failedCompletion
            ? ["type": "task_complete", "turn_id": "interrupted", "duration_ms": 10_000, "error": "synthetic failure"]
            : ["type": "turn_aborted", "turn_id": "interrupted"]
        data.append(try line(["timestamp": formatter.string(from: now.addingTimeInterval(-5)), "type": "event_msg", "payload": terminal]))
        if replaceWithValid {
            let other = try rollout(temporaryHome(), number: 2, tokens: 700, age: 4)
            let otherLines = try Data(contentsOf: other).split(separator: 0x0A)
            data.append(contentsOf: otherLines[1]); data.append(0x0A)
        }
        try data.write(to: path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-5)], ofItemAtPath: path.path)
        let ended = try await monitor.poll(now: now)
        if replaceWithValid { XCTAssertEqual(ended.latestSample?.tokensPerSecond, 70) }
        else { XCTAssertNil(ended.latestSample) }
        XCTAssertEqual(ended.unsupportedSessionCount, 0)
        let repeated = try await monitor.poll(now: now)
        if replaceWithValid { XCTAssertEqual(repeated.latestSample?.tokensPerSecond, 70) }
        else { XCTAssertNil(repeated.latestSample) }
    }
}
