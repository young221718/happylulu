import XCTest
@testable import AIUsagePlugin

final class StatusLineProviderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)
    private let claude = #"{"schema":1,"provider":"claude","observedAt":1900000000,"rate_limits":{"five_hour":{"used_percentage":99,"resets_at":1900001000},"seven_day":{"used_percentage":41.2,"resets_at":1900600000}}}"#

    func testBundledHelperProducesAnImportablePrivateReportWithoutRawSessionData() async throws {
        let helper = try XCTUnwrap(StatusLineUsageProvider.exporterURL)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("usage.json")
        let process = Process(), input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [helper.path, "--provider", "claude", "--output", output.path]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        let reset = Date().addingTimeInterval(3600).timeIntervalSince1970
        try input.fileHandleForWriting.write(contentsOf: Data("{\"session_id\":\"private\",\"transcript_path\":\"/private/chat\",\"rate_limits\":{\"seven_day\":{\"used_percentage\":41.2,\"resets_at\":\(reset)}}}".utf8))
        try input.fileHandleForWriting.close(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let bytes = try Data(contentsOf: output)
        XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("private"))
        let value = try await StatusLineUsageProvider(providerID: "claude", name: "Claude", reportPath: output.path).fetch()
        XCTAssertEqual(value.weekly.remainingPercent, 58)
    }

    func testClaudeUsesWeeklyQuotaInsteadOfContextOrFiveHourLimit() throws {
        let value = try StatusLineUsageProvider.parse(Data(claude.utf8), providerID: "claude", now: now)
        XCTAssertEqual(value.weekly.remainingPercent, 58)
        XCTAssertEqual(value.weekly.windowDurationMins, 10_080)
        XCTAssertEqual(value.fetchedAt, now)
        XCTAssertNil(value.accountKey, "Claude's statusLine does not identify the account")
    }

    func testAntigravityReadsOfficialQuotaBucketAndKeepsOnlyFingerprint() throws {
        let raw = #"{"schema":1,"provider":"antigravity","observedAt":1900000000,"accountKey":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","quota":{"gemini-weekly":{"remaining_fraction":0.9378,"reset_time":"2030-03-23T17:46:40Z"},"gemini-pro":{"remaining_fraction":0.01,"reset_time":"2030-03-23T17:46:40Z"}}}"#
        let value = try StatusLineUsageProvider.parse(Data(raw.utf8), providerID: "antigravity", now: now)
        XCTAssertEqual(value.weekly.remainingPercent, 93)
        XCTAssertEqual(value.accountKey, String(repeating: "a", count: 64))
    }

    func testAntigravityWholePercentDoesNotLoseAPointToFloatingArithmetic() throws {
        let raw = #"{"schema":1,"provider":"antigravity","observedAt":1900000000,"quota":{"gemini-weekly":{"remaining_fraction":0.58,"reset_time":"2030-03-23T17:46:40Z"}}}"#
        let value = try StatusLineUsageProvider.parse(Data(raw.utf8), providerID: "antigravity", now: now)
        XCTAssertEqual(value.weekly.remainingPercent, 58)
    }

    func testMissingWeeklyQuotaNeverBecomesZeroUsage() {
        for raw in [
            #"{"schema":1,"provider":"claude","observedAt":1900000000,"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":1900001000}}}"#,
            #"{"schema":1,"provider":"antigravity","observedAt":1900000000,"quota":{"gemini-weekly":{"remaining_fraction":1,"reset_time":"2030-03-23T17:46:40Z","disabled":true}}}"#
        ] {
            XCTAssertThrowsError(try StatusLineUsageProvider.parse(Data(raw.utf8),
                providerID: raw.contains("antigravity") ? "antigravity" : "claude", now: now))
        }
    }

    func testWrongProviderStaleFutureExpiredAndMalformedQuotasAreRejected() {
        let replacements = [
            ("\"claude\"", "\"codex\""), ("\"schema\":1", "\"schema\":2"),
            ("1900000000", "1899999000"), ("1900000000", "1900000100"),
            ("1900600000", "1899999999"), ("41.2", "101"), ("41.2", "true"),
            ("41.2", "null"), ("1900600000", "1e100")
        ]
        for (from, to) in replacements {
            XCTAssertThrowsError(try StatusLineUsageProvider.parse(Data(claude.replacingOccurrences(of: from, with: to).utf8),
                providerID: "claude", now: now), "Accepted invalid report: \(from) -> \(to)")
        }
    }

    func testReaderRejectsLinksPublicFilesAndCancellation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = directory.appendingPathComponent("usage.json")
        let now = Date().timeIntervalSince1970
        let raw = "{\"schema\":1,\"provider\":\"claude\",\"observedAt\":\(now),\"rate_limits\":{\"seven_day\":{\"used_percentage\":20,\"resets_at\":\(now + 3600)}}}"
        try Data(raw.utf8).write(to: report)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: report.path)
        let provider = StatusLineUsageProvider(providerID: "claude", name: "Claude", reportPath: report.path)
        let value = try await provider.fetch()
        XCTAssertEqual(value.weekly.remainingPercent, 80)
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: report)
        do {
            _ = try await StatusLineUsageProvider(providerID: "claude", name: "Claude", reportPath: link.path).fetch()
            XCTFail("A symlink must not be followed")
        } catch {}
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: report.path)
        do { _ = try await provider.fetch(); XCTFail("Public usage file accepted") } catch {}
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await provider.fetch()
        }
        do { _ = try await cancelled.value; XCTFail("Cancelled fetch accepted") } catch is CancellationError {} catch { XCTFail("\(error)") }
    }
}
