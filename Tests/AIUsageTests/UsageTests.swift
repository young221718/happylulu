import XCTest
@testable import AIUsagePlugin

final class UsageTests: XCTestCase {
    private func response(_ json: String) throws -> RateLimitsResponse {
        try JSONDecoder().decode(RateLimitsResponse.self, from: Data(json.utf8))
    }

    func testSelectsWeeklyByDurationAndPrefersCodexBucket() throws {
        let result = try response(#"""
        {
          "rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":10080}},
          "rateLimitsByLimitId":{
            "codex":{"primary":{"usedPercent":5,"windowDurationMins":300},
                     "secondary":{"usedPercent":28,"windowDurationMins":10080,"resetsAt":2000000000}},
            "codex_other":{"primary":{"usedPercent":90,"windowDurationMins":10080}}
          }
        }
        """#)
        let weekly = try result.weeklyWindow()
        XCTAssertEqual(weekly.remainingPercent, 72)
        XCTAssertEqual(weekly.resetsAt, 2_000_000_000)
    }

    func testWeeklyCanBePrimaryAndMissingResetDoesNotInventDate() throws {
        let result = try response(#"{"rateLimits":{"primary":{"usedPercent":40,"windowDurationMins":10080},"secondary":null}}"#)
        let weekly = try result.weeklyWindow()
        XCTAssertEqual(weekly.remainingPercent, 60)
        XCTAssertNil(weekly.resetDate)
    }

    func testNoShortWindowFallbackAndNoUnrelatedBucketFallback() throws {
        let short = try response(#"{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":300}}}"#)
        XCTAssertThrowsError(try short.weeklyWindow())
        let unrelated = try response(#"{"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":10,"windowDurationMins":10080}}}}"#)
        XCTAssertThrowsError(try unrelated.weeklyWindow())
        let unknownDuration = try response(#"{"rateLimits":{"secondary":{"usedPercent":10}}}"#)
        XCTAssertThrowsError(try unknownDuration.weeklyWindow())
    }

    func testRemainingPercentClampsAndRoundsDown() {
        for (used, remaining) in [(0.0, 100), (27.2, 72), (99.6, 0), (120, 0), (-10, 100)] {
            XCTAssertEqual(UsageWindow(usedPercent: used, windowDurationMins: 10080, resetsAt: nil).remainingPercent, remaining)
        }
    }

    func testStalenessIncludesResetBoundary() {
        let window = UsageWindow(usedPercent: 20, windowDurationMins: 10080, resetsAt: 1500)
        let snapshot = UsageSnapshot(weekly: window, fetchedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertFalse(snapshot.isStale(at: Date(timeIntervalSince1970: 1499), intervalMinutes: 5))
        XCTAssertTrue(snapshot.isStale(at: Date(timeIntervalSince1970: 1500), intervalMinutes: 5))
        let noReset = UsageSnapshot(weekly: UsageWindow(usedPercent: 20, windowDurationMins: 10080, resetsAt: nil),
                                    fetchedAt: Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(noReset.isStale(at: Date(timeIntervalSince1970: 1600), intervalMinutes: 5))
    }

    func testUnknownValueIsNeverZeroAndStaleValueIsMarked() {
        XCTAssertEqual(LabelFormat.named.title(remaining: nil), "Codex —")
        XCTAssertEqual(LabelFormat.percentage.title(remaining: 72), "72%")
        XCTAssertEqual(LabelFormat.named.title(remaining: 72, stale: true), "Codex 72% ·")
    }

    func testIconTitleRetainsUnknownAndStaleMeaningWithTextFallback() throws {
        let format = try JSONDecoder().decode(LabelFormat.self, from: Data(#""icon""#.utf8))
        XCTAssertEqual(format.title(remaining: 72, iconAvailable: true), "72%")
        XCTAssertEqual(format.title(remaining: nil, iconAvailable: true), "—")
        XCTAssertEqual(format.title(remaining: 72, stale: true, iconAvailable: true), "72% ·")
        XCTAssertEqual(format.title(remaining: 72), "Codex 72%")
        XCTAssertEqual(format.title(remaining: nil, stale: true), "Codex —")
    }

    func testNotificationOncePerWindowAndThresholdAfterDelivery() {
        var gate = LowUsageAlertGate()
        let window = UsageWindow(usedPercent: 85, windowDurationMins: 10080, resetsAt: 2000)
        XCTAssertNil(gate.pendingKey(for: window, threshold: 10, enabled: true))
        XCTAssertNil(gate.pendingKey(for: window, threshold: 20, enabled: false))
        let key = gate.pendingKey(for: window, threshold: 20, enabled: true)!
        XCTAssertEqual(gate.pendingKey(for: window, threshold: 20, enabled: true), key)
        gate.markDelivered(key)
        XCTAssertNil(gate.pendingKey(for: window, threshold: 20, enabled: true))
        XCTAssertNotNil(gate.pendingKey(for: UsageWindow(usedPercent: 90, windowDurationMins: 10080, resetsAt: 3000),
                                       threshold: 20, enabled: true))
        let restored = LowUsageAlertGate(deliveredKey: key)
        XCTAssertNil(restored.pendingKey(for: window, threshold: 20, enabled: true))
    }

    func testIconPreferenceDecodesWithoutChangingExistingSettings() throws {
        let stored = Data(#"{"refreshMinutes":15,"labelFormat":"icon","notificationsEnabled":true,"notificationThreshold":30,"cliPath":"/fixture/codex"}"#.utf8)
        let preferences = try JSONDecoder().decode(Preferences.self, from: stored)
        XCTAssertEqual(preferences.labelFormat.rawValue, "icon")
        XCTAssertEqual(preferences.refreshMinutes, 15)
        XCTAssertTrue(preferences.notificationsEnabled)
        XCTAssertEqual(preferences.notificationThreshold, 30)
        XCTAssertEqual(preferences.cliPath, "/fixture/codex")
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)), preferences)
    }

    func testExistingLabelPreferencesKeepSavedMeaningAndDefault() throws {
        XCTAssertEqual(Preferences().labelFormat, .named)
        for format in ["named", "percentage"] {
            let stored = Data("{\"refreshMinutes\":10,\"labelFormat\":\"\(format)\",\"notificationsEnabled\":false,\"notificationThreshold\":20,\"cliPath\":\"\"}".utf8)
            let preferences = try JSONDecoder().decode(Preferences.self, from: stored)
            XCTAssertEqual(preferences.labelFormat.rawValue, format)
            XCTAssertEqual(preferences.refreshMinutes, 10)
        }
    }

    func testPreferencesNormalizeBadStoredValues() {
        var preferences = Preferences()
        preferences.refreshMinutes = -10
        preferences.notificationThreshold = 200
        preferences.cliPath = "  /tmp/codex  \n"
        preferences.normalize()
        XCTAssertEqual(preferences.refreshMinutes, 5)
        XCTAssertEqual(preferences.notificationThreshold, 20)
        XCTAssertEqual(preferences.cliPath, "/tmp/codex")
    }
}
