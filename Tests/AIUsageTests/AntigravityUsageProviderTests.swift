import XCTest
import Darwin
@testable import AIUsagePlugin

final class AntigravityUsageProviderTests: XCTestCase {
    private var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func report(_ bucket: String) -> Data {
        Data("""
        {"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"buckets":[\(bucket)]}]}}}
        """.utf8)
    }

    private var validReport: Data {
        report(#"{"bucket_id":"gemini-weekly","remaining":{"case":"remainingFraction","value":0.82},"reset_time":"2033-05-18T03:33:20Z"}"#)
    }

    private func write(_ data: Data, age: TimeInterval = 30) throws -> URL {
        let url = directory.appendingPathComponent("usage.json")
        try data.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
        return url
    }

    func testReadsSelectedReportAndPreservesSourceTimeWithoutAccountIdentity() async throws {
        let url = try write(validReport)
        let sourceDate = try XCTUnwrap(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        let result = try await AntigravityUsageProvider(executablePath: "/must-not-execute", configDirectory: url.path).fetch()
        XCTAssertEqual(result.weekly.remainingPercent, 82)
        XCTAssertEqual(result.weekly.windowDurationMins, 10_080)
        XCTAssertEqual(result.weekly.resetsAt, 2_000_000_000)
        XCTAssertEqual(result.fetchedAt.timeIntervalSince1970, sourceDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertNil(result.accountKey)
        XCTAssertNil(AntigravityUsageProvider().makeLoginAttempt())
    }

    func testSessionUnknownDisabledAndOtherModelBucketsAreNotGeminiWeekly() {
        for bucket in [
            #"{"bucketId":"gemini-5h","remainingFraction":0.2}"#,
            #"{"bucketId":"3p-weekly","remainingFraction":0.2}"#,
            #"{"bucketId":"unknown-weekly","remainingFraction":0.2}"#,
            #"{"bucketId":"gemini-weekly","remainingFraction":0.2,"disabled":true}"#
        ] {
            XCTAssertThrowsError(try AntigravityUsageProvider.parseUsageReport(report(bucket)))
        }
    }

    func testMalformedOrUnsuccessfulReportsAreRejected() {
        let bucket = #"{"bucketId":"gemini-weekly","remainingFraction":0.5,"resetTime":"2033-05-18T03:33:20Z"}"#
        for data in [Data("{}".utf8), Data("invalid".utf8),
                     Data(String(data: report(bucket), encoding: .utf8)!.replacingOccurrences(of: "SUCCESS", with: "ERROR").utf8),
                     report(bucket.replacingOccurrences(of: "0.5", with: "2")),
                     report(bucket.replacingOccurrences(of: "2033-05-18T03:33:20Z", with: "bad")),
                     report(bucket + "," + bucket)] {
            XCTAssertThrowsError(try AntigravityUsageProvider.parseUsageReport(data))
        }
    }

    func testMissingRelativeAndDirectoryPathsAreRejected() async throws {
        for path in ["", "usage.json", "~/usage.json", directory.path, directory.appendingPathComponent("missing.json").path] {
            do { _ = try await AntigravityUsageProvider(configDirectory: path).fetch(); XCTFail("Invalid report path") }
            catch { XCTAssertEqual(error as? AntigravityUsageError, .reportUnavailable) }
        }
    }

    func testOldAndFutureReportsAreRejected() async throws {
        for age in [901.0, -30.0] {
            let url = try write(validReport, age: age)
            do { _ = try await AntigravityUsageProvider(configDirectory: url.path).fetch(); XCTFail("Invalid report date") }
            catch { XCTAssertEqual(error as? AntigravityUsageError, age > 0 ? .staleReport : .futureReport) }
        }
    }

    func testExpiredQuotaIsRejected() async throws {
        let expired = report(#"{"bucketId":"gemini-weekly","remainingFraction":0.2,"resetTime":"2020-01-01T00:00:00Z"}"#)
        let url = try write(expired)
        do { _ = try await AntigravityUsageProvider(configDirectory: url.path).fetch(); XCTFail("Expired quota") }
        catch { XCTAssertEqual(error as? AntigravityUsageError, .staleReport) }
    }

    func testOversizedAndSymlinkReportsAreRejected() async throws {
        let url = try write(Data(repeating: 0x20, count: 1_048_577))
        do { _ = try await AntigravityUsageProvider(configDirectory: url.path).fetch(); XCTFail("Oversized report") }
        catch { XCTAssertEqual(error as? AntigravityUsageError, .invalidResponse) }
        let target = try write(validReport)
        let link = directory.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        do { _ = try await AntigravityUsageProvider(configDirectory: link.path).fetch(); XCTFail("Symlink report") }
        catch { XCTAssertEqual(error as? AntigravityUsageError, .reportUnavailable) }
    }

    func testCancelledFetchDoesNotReadReport() async throws {
        let url = try write(validReport)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await AntigravityUsageProvider(configDirectory: url.path).fetch()
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    private func executable(_ body: String) throws -> String {
        let url = directory.appendingPathComponent("fake-agy")
        try ("#!/usr/bin/python3\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }

    func testCLIIsNeverLaunchedWithoutExplicitOptIn() async throws {
        let marker = directory.appendingPathComponent("launched")
        let path = try executable("open('\(marker.path)','w').write('launched')")
        do { _ = try await AntigravityUsageProvider(executablePath: path).fetch(); XCTFail("Expected report selection") }
        catch { XCTAssertEqual(error as? AntigravityUsageError, .reportUnavailable) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testOptedInCLIRunsOnlyReadOnlyReportWithGuards() async throws {
        let payload = String(data: validReport, encoding: .utf8)!
        let path = try executable("""
        import sys,os,subprocess
        assert os.environ['AGY_CLI_DISABLE_AUTO_UPDATE']=='true'
        assert subprocess.call(['open','https://example.invalid']) != 0
        assert subprocess.call([os.environ['BROWSER'],'https://example.invalid']) != 0
        assert os.getcwd().startswith('/private/') or os.getcwd().startswith('/var/')
        if sys.argv[1:]==['--version']: print('1.1.11')
        else:
            assert sys.argv[1:]==['-p','/usage','--output-format','json']
            print('\(payload)')
        """)
        let value = try await AntigravityUsageProvider(executablePath: path, allowCLIExecution: true, timeout: 2).fetch()
        XCTAssertEqual(value.weekly.remainingPercent, 82)
        XCTAssertNil(value.accountKey)
    }

    func testOldOrUnknownCLICannotTurnUsageIntoModelPrompt() async throws {
        for version in ["1.1.10", "unknown", "1.1.11-beta.1"] {
            let path = try executable("""
            import sys
            assert sys.argv[1:]==['--version']
            print('\(version)')
            """)
            do { _ = try await AntigravityUsageProvider(executablePath: path, allowCLIExecution: true, timeout: 2).fetch(); XCTFail("Unsupported version") }
            catch { XCTAssertEqual(error as? AntigravityUsageError, .unsupportedVersion) }
        }
    }

    func testFailedCLIFallsBackOnlyToExplicitFreshReport() async throws {
        let url = try write(validReport)
        let path = try executable("import sys\nsys.exit(1)")
        let result = try await AntigravityUsageProvider(executablePath: path, configDirectory: url.path,
                                                       allowCLIExecution: true, timeout: 2).fetch()
        XCTAssertEqual(result.weekly.remainingPercent, 82)
    }

    func testCLITimeoutIsBounded() async throws {
        let path = try executable("import time\ntime.sleep(30)")
        let start = Date()
        do { _ = try await AntigravityUsageProvider(executablePath: path, allowCLIExecution: true, timeout: 0.3).fetch(); XCTFail("Expected timeout") }
        catch { XCTAssertEqual(error as? AntigravityUsageError, .timeout) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testOversizedCLIVersionOutputIsRejected() async throws {
        let path = try executable("print('x'*1100000)")
        // Output-limit checks must allow interpreter startup under concurrent build load.
        do { _ = try await AntigravityUsageProvider(executablePath: path, allowCLIExecution: true, timeout: 10).fetch(); XCTFail("Expected output limit") }
        catch { XCTAssertEqual(error as? AntigravityUsageError, .invalidResponse) }
    }

    func testOversizedValidCLIUsageReportIsRejected() async throws {
        let payload = String(data: validReport, encoding: .utf8)!
        let path = try executable("""
        import sys,json
        if sys.argv[1:]==['--version']: print('1.1.11')
        else:
            assert sys.argv[1:]==['-p','/usage','--output-format','json']
            payload=json.loads('\(payload)')
            payload['padding']='x'*1100000
            print(json.dumps(payload))
        """)
        do { _ = try await AntigravityUsageProvider(executablePath: path, allowCLIExecution: true, timeout: 10).fetch(); XCTFail("Expected output limit") }
        catch { XCTAssertEqual(error as? AntigravityUsageError, .invalidResponse) }
    }

    func testCancellationKillsOwnedCLIProcessGroupAndDoesNotFallBack() async throws {
        let marker = directory.appendingPathComponent("pid").path
        let survivor = directory.appendingPathComponent("survivor").path
        let path = try executable("""
        import os,time,subprocess,sys
        subprocess.Popen([sys.executable,'-c',"import time;time.sleep(0.8);open('\(survivor)','w').write('survived')"])
        open('\(marker)','w').write(str(os.getpid()))
        time.sleep(30)
        """)
        let report = try write(validReport)
        let task = Task {
            try await AntigravityUsageProvider(executablePath: path, configDirectory: report.path,
                                               allowCLIExecution: true, timeout: 5).fetch()
        }
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: marker) { try await Task.sleep(nanoseconds: 10_000_000) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let pid = try XCTUnwrap(Int32(String(contentsOfFile: marker, encoding: .utf8)))
        XCTAssertEqual(kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: survivor), "Owned child escaped cancellation")
    }

}
