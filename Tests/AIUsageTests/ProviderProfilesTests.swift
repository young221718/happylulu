import XCTest
@testable import AIUsagePlugin
@testable import AIUsageIntegration

private actor ProfileCodexCounter {
    var count = 0
    func fetch() throws -> UsageSnapshot { count += 1; throw UsageError.notLoggedIn }
}
private struct CountingCodexProvider: UsageProvider {
    let name = "Codex"
    let counter: ProfileCodexCounter
    func fetch() async throws -> UsageSnapshot { try await counter.fetch() }
    func makeLoginAttempt() -> (any UsageLoginAttempt)? { nil }
}

@MainActor
final class ProviderProfilesTests: XCTestCase {
    private func eventually(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !predicate() {
            guard Date() < deadline else { XCTFail("Provider reading did not arrive"); return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func testClaudeProfileReadsExportWithoutCallingCodexOrCreatingAccountHistory() async throws {
        let name = "test.happylulu.profiles." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        let report = directory.appendingPathComponent("claude.json")
        let observed = floor(Date().timeIntervalSince1970) - 60
        try Data("{\"schema\":1,\"provider\":\"claude\",\"observedAt\":\(observed),\"rate_limits\":{\"seven_day\":{\"used_percentage\":41.2,\"resets_at\":\(observed + 3600)}}}".utf8).write(to: report)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: report.path)
        let counter = ProfileCodexCounter()
        var notificationChecks = 0
        let model = AIUsageModel(defaults: defaults, providerFactory: { _ in CountingCodexProvider(counter: counter) },
            notificationAuthorization: { notificationChecks += 1; return true })
        defer { model.stop() }
        let id = try XCTUnwrap(model.addProfile(providerID: "claude"))
        model.updateSelectedProfile { $0.reportPath = report.path }
        model.updatePreferences { $0.labelFormat = .icon; $0.notificationsEnabled = true }
        model.setEnabled(true); model.start()
        try await eventually { !model.isRunning && model.snapshot != nil }
        XCTAssertEqual(model.menuBarItem?.title, "Claude 58%")
        XCTAssertNil(model.menuBarItem?.iconPNG)
        XCTAssertEqual(model.snapshot?.fetchedAt.timeIntervalSince1970, observed)
        XCTAssertFalse(model.supportsNotifications)
        XCTAssertEqual(notificationChecks, 0)
        XCTAssertNil(defaults.data(forKey: "HappyLuluAIUsage.providers.v2.\(id).history.v1"))
        let calls = await counter.count
        XCTAssertEqual(calls, 0)
    }

    func testNewCodexConnectionRequiresExplicitFolderAndPreservesReleasedAndLegacyBytes() throws {
        let name = "test.happylulu.profiles." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let legacy = Data(#"{"profiles":[],"selectedProfileID":"old"}"#.utf8)
        defaults.set(legacy, forKey: "HappyLuluAIUsage.preferences.v1")
        let model = AIUsageModel(defaults: defaults)
        let release = defaults.data(forKey: ReleasedUsagePreferences.key)
        let id = try XCTUnwrap(model.addProfile(providerID: "codex"))
        XCTAssertFalse(model.canRequestUsage)
        model.updatePreferences { $0.cliPath = "/fixture/codex" }
        XCTAssertFalse(model.canRequestUsage, "A new profile must not silently reuse the default CLI account")
        model.updateSelectedProfile { $0.preferences.configDirectory = "/fixture/isolated-account" }
        XCTAssertTrue(model.canRequestUsage)
        XCTAssertEqual(defaults.data(forKey: ReleasedUsagePreferences.key), release)
        XCTAssertEqual(defaults.data(forKey: "HappyLuluAIUsage.preferences.v1"), legacy)
        let restored = AIUsageModel(defaults: defaults)
        XCTAssertEqual(restored.selectedProfile?.id, id)
        XCTAssertEqual(restored.preferences.configDirectory, "/fixture/isolated-account")
        restored.selectProfile(nil)
        XCTAssertFalse(restored.canRequestUsage, "The ambiguous legacy account remains blocked")
        XCTAssertEqual(defaults.data(forKey: "HappyLuluAIUsage.preferences.v1"), legacy)
    }

    func testMalformedAndUnknownProviderStoreIsReadOnlyWithoutFallbackOrRewrite() throws {
        let name = "test.happylulu.profiles." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = UsageProfileSettings()
        let profile = UsageProfile(providerID: "claude", name: "Claude")
        settings.profiles = [profile]; settings.selectedID = profile.id
        let encoded = try JSONEncoder().encode(settings)
        var objects: [[String: Any]] = []
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let originalProfiles = try XCTUnwrap(original["profiles"] as? [[String: Any]])
        var missingSelection = original; missingSelection.removeValue(forKey: "selectedID"); objects.append(missingSelection)
        var wrongSelection = original; wrongSelection["selectedID"] = "missing"; objects.append(wrongSelection)
        var duplicate = original; duplicate["profiles"] = originalProfiles + originalProfiles; objects.append(duplicate)
        for (field, value) in [("providerID", "future-provider"), ("id", "../unsafe"), ("preferences", [:])] as [(String, Any)] {
            var object = original
            var profiles = try XCTUnwrap(object["profiles"] as? [[String: Any]])
            profiles[0][field] = value; object["profiles"] = profiles; objects.append(object)
        }
        for object in objects {
            let data = try JSONSerialization.data(withJSONObject: object)
            defaults.set(data, forKey: UsageProfileSettings.key)
            let model = AIUsageModel(defaults: defaults)
            XCTAssertTrue(model.settingsReadOnly)
            XCTAssertFalse(model.canRequestUsage)
            XCTAssertNil(model.addProfile(providerID: "codex"))
            model.selectProfile(nil); model.removeSelectedProfile()
            XCTAssertEqual(defaults.data(forKey: UsageProfileSettings.key), data)
        }
    }

    func testExplicitProfileRemovalPreservesOtherConnections() throws {
        let name = "test.happylulu.profiles." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = AIUsageModel(defaults: defaults)
        let first = try XCTUnwrap(model.addProfile(providerID: "claude"))
        model.updateSelectedProfile { $0.reportPath = "/fixture/claude.json" }
        _ = model.addProfile(providerID: "antigravity")
        model.removeSelectedProfile()
        XCTAssertNil(model.selectedProfile)
        let restored = AIUsageModel(defaults: defaults)
        XCTAssertEqual(restored.profileSettings.profiles.map(\.id), [first])
        restored.selectProfile(first)
        XCTAssertEqual(restored.selectedProfile?.reportPath, "/fixture/claude.json")
    }
}
