import XCTest
@testable import AIUsagePlugin
@testable import AIUsageIntegration

private actor ReleaseFetchCounter {
    var count = 0
    func fetch() -> UsageSnapshot {
        count += 1
        return UsageSnapshot(weekly: UsageWindow(usedPercent: 25, windowDurationMins: 10_080,
            resetsAt: Date().addingTimeInterval(3600).timeIntervalSince1970), accountKey: "fixture")
    }
}

private struct ReleaseProvider: UsageProvider {
    let name = "Codex"
    let counter: ReleaseFetchCounter
    func fetch() async throws -> UsageSnapshot { await counter.fetch() }
    func makeLoginAttempt() -> (any UsageLoginAttempt)? { nil }
}

@MainActor
final class ReleasedPreferencesTests: XCTestCase {
    private let oldKey = "HappyLuluAIUsage.preferences.v1"
    private let newKey = "HappyLuluAIUsage.codex-release.preferences.v1"

    private func fixture(_ body: @MainActor (UserDefaults) async throws -> Void) async throws {
        let name = "test.happylulu.release-preferences." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try await body(defaults)
    }

    func testPublishedSettingsAreCopiedWithoutRewritingTheirOriginalBytes() async throws {
        try await fixture { defaults in
            let original = Data(#"{"refreshMinutes":10,"labelFormat":"named","notificationsEnabled":false,"notificationThreshold":20,"cliPath":"/fixture/codex"}"#.utf8)
            defaults.set(original, forKey: oldKey)
            let model = AIUsageModel(defaults: defaults)
            XCTAssertEqual(model.preferences.cliPath, "/fixture/codex")
            model.updatePreferences { $0.labelFormat = .percentage }
            XCTAssertEqual(defaults.data(forKey: oldKey), original)
            XCTAssertNotNil(defaults.data(forKey: newKey))
            XCTAssertEqual(AIUsageModel(defaults: defaults).preferences.labelFormat, .percentage)
        }
    }

    func testUnsupportedSelectedProfileNeverStartsCodexOrMutatesPreviousState() async throws {
        try await fixture { defaults in
            let original = Data(#"{"refreshMinutes":5,"labelFormat":"named","notificationsEnabled":false,"notificationThreshold":20,"cliPath":"/fixture/agy","selectedProfileID":"other","profiles":[{"id":"codex","provider":"codex","cliPath":"/fixture/codex","configDirectory":"/fixture/home"},{"id":"other","provider":"antigravity","cliPath":"/fixture/agy","configDirectory":""}]}"#.utf8)
            defaults.set(original, forKey: oldKey)
            let history = Data("preserved previous profile history".utf8)
            defaults.set(history, forKey: "HappyLuluAIUsage.history.v1")
            defaults.set("previous", forKey: "HappyLuluAIUsage.notificationAccount.v1")
            let counter = ReleaseFetchCounter()
            let model = AIUsageModel(defaults: defaults, providerFactory: { _ in ReleaseProvider(counter: counter) })
            model.setEnabled(true); model.start(); model.refreshData(); model.login()
            try await Task.sleep(for: .milliseconds(80))
            let count = await counter.count
            XCTAssertEqual(count, 0)
            model.updatePreferences { $0.labelFormat = .percentage }
            model.stop()
            XCTAssertEqual(defaults.data(forKey: oldKey), original)
            XCTAssertEqual(defaults.data(forKey: "HappyLuluAIUsage.history.v1"), history)
            XCTAssertEqual(defaults.string(forKey: "HappyLuluAIUsage.notificationAccount.v1"), "previous")
            let restarted = AIUsageModel(defaults: defaults, providerFactory: { _ in ReleaseProvider(counter: counter) })
            restarted.setEnabled(true); restarted.start()
            try await Task.sleep(for: .milliseconds(30))
            restarted.stop()
            let restartedCount = await counter.count
            XCTAssertEqual(restartedCount, 0)
        }
    }

    func testSelectedCodexKeepsItsExecutableAndAccountFolder() async throws {
        try await fixture { defaults in
            let original = Data(#"{"cliPath":"/wrong/top-level","selectedProfileID":"selected","profiles":[{"id":"selected","provider":"codex","cliPath":"/fixture/codex","configDirectory":"/fixture/account"}]}"#.utf8)
            defaults.set(original, forKey: oldKey)
            let model = AIUsageModel(defaults: defaults)
            XCTAssertTrue(model.canRequestUsage)
            XCTAssertEqual(model.preferences.cliPath, "/fixture/codex")
            XCTAssertEqual(model.preferences.configDirectory, "/fixture/account")
            model.updatePreferences { $0.refreshMinutes = 10 }
            let restarted = AIUsageModel(defaults: defaults)
            XCTAssertEqual(restarted.preferences.configDirectory, "/fixture/account")
            XCTAssertEqual(restarted.preferences.refreshMinutes, 10)
            XCTAssertEqual(defaults.data(forKey: oldKey), original)
        }
    }

    func testMalformedNewSettingsStayReadOnlyWithoutFallingBackToOldAccount() async throws {
        try await fixture { defaults in
            let corrupt = Data("{corrupt".utf8)
            defaults.set(corrupt, forKey: newKey)
            defaults.set(try JSONEncoder().encode(Preferences()), forKey: oldKey)
            let counter = ReleaseFetchCounter()
            let model = AIUsageModel(defaults: defaults, providerFactory: { _ in ReleaseProvider(counter: counter) })
            XCTAssertTrue(model.settingsReadOnly)
            XCTAssertFalse(model.canRequestUsage)
            model.updatePreferences { $0.refreshMinutes = 10 }
            XCTAssertThrowsError(try model.acceptExecutable("/usr/bin/true"))
            model.setEnabled(true); model.start(); model.refreshData(); model.login()
            try await Task.sleep(for: .milliseconds(30)); model.stop()
            let count = await counter.count
            XCTAssertEqual(count, 0)
            XCTAssertEqual(defaults.data(forKey: newKey), corrupt)
        }
    }

    func testAmbiguousOrUnsupportedProfilesRequireAnExplicitConnection() async throws {
        for raw in [
            #"{"profiles":[],"selectedProfileID":"missing"}"#,
            #"{"profiles":[{"id":"a","provider":"claude","cliPath":"/fixture/claude","configDirectory":""}],"selectedProfileID":"a"}"#,
            #"{"profiles":[{"id":"a","provider":"codex","cliPath":"","configDirectory":"relative"}],"selectedProfileID":"a"}"#,
            #"{"profiles":[{"id":"a","provider":"codex","cliPath":"","configDirectory":""},{"id":"a","provider":"codex","cliPath":"","configDirectory":""}],"selectedProfileID":"a"}"#
        ] {
            try await fixture { defaults in
                let data = Data(raw.utf8)
                defaults.set(data, forKey: oldKey)
                XCTAssertFalse(AIUsageModel(defaults: defaults).canRequestUsage)
                XCTAssertEqual(defaults.data(forKey: oldKey), data)
            }
        }
    }

    func testChoosingCodexEnablesOnlyTheNewConnectionAndSurvivesRestart() async throws {
        try await fixture { defaults in
            let original = Data(#"{"profiles":[],"selectedProfileID":"missing"}"#.utf8)
            defaults.set(original, forKey: oldKey)
            let counter = ReleaseFetchCounter()
            let model = AIUsageModel(defaults: defaults, providerFactory: { _ in ReleaseProvider(counter: counter) })
            model.setEnabled(true); model.start()
            try model.acceptExecutable("/usr/bin/true")
            try await Task.sleep(for: .milliseconds(50)); model.stop()
            let count = await counter.count
            XCTAssertEqual(count, 1)
            XCTAssertEqual(defaults.data(forKey: oldKey), original)
            XCTAssertTrue(AIUsageModel(defaults: defaults).canRequestUsage)
        }
    }

    func testPartialNewJSONCannotSilentlySelectTheDefaultAccount() async throws {
        for raw in [
            #"{"schema":1,"requiresConnection":false,"preferences":{}}"#,
            #"{"schema":1,"requiresConnection":false,"preferences":{"refreshMinutes":5,"labelFormat":"named","notificationsEnabled":false,"notificationThreshold":20,"cliPath":"/fixture/codex"}}"#
        ] {
            try await fixture { defaults in
                let data = Data(raw.utf8)
                defaults.set(data, forKey: newKey)
                let model = AIUsageModel(defaults: defaults)
                XCTAssertTrue(model.settingsReadOnly)
                XCTAssertFalse(model.canRequestUsage)
                model.updatePreferences { $0.refreshMinutes = 10 }
                XCTAssertEqual(defaults.data(forKey: newKey), data)
            }
        }
    }

    func testUnknownLegacyObjectIsPreservedWithoutAutomaticConnection() async throws {
        try await fixture { defaults in
            let data = Data("{}".utf8)
            defaults.set(data, forKey: oldKey)
            XCTAssertFalse(AIUsageModel(defaults: defaults).canRequestUsage)
            XCTAssertEqual(defaults.data(forKey: oldKey), data)
        }
    }

    func testCorruptProviderSettingsCannotFallBackToReleasedAccount() async throws {
        for raw in ["{corrupt", #"{"schema":99,"profiles":[],"selectedID":null}"#] {
            try await fixture { defaults in
                let data = Data(raw.utf8)
                defaults.set(data, forKey: "HappyLuluAIUsage.providers.v2")
                let counter = ReleaseFetchCounter()
                let model = AIUsageModel(defaults: defaults, providerFactory: { _ in ReleaseProvider(counter: counter) })
                model.setEnabled(true); model.start(); model.login(); model.refreshData()
                try await Task.sleep(for: .milliseconds(30)); model.stop()
                let count = await counter.count
                XCTAssertEqual(count, 0)
                XCTAssertTrue(model.settingsReadOnly)
                XCTAssertEqual(defaults.data(forKey: "HappyLuluAIUsage.providers.v2"), data)
            }
        }
    }
}
