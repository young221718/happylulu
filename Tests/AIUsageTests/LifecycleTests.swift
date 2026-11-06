import XCTest
import Combine
import AppPluginHost
@testable import AIUsagePlugin
@testable import AIUsageIntegration

private actor DeferredProvider: UsageProvider {
    nonisolated let name = "Fixture"
    nonisolated let loginAttempt: DeferredLogin?
    init(loginAttempt: DeferredLogin? = nil) { self.loginAttempt = loginAttempt }
    private var requests: [Int: CheckedContinuation<UsageSnapshot, Error>] = [:]
    private(set) var count = 0
    private(set) var cancellations = 0
    nonisolated func makeLoginAttempt() -> (any UsageLoginAttempt)? { loginAttempt }
    func fetch() async throws -> UsageSnapshot {
        count += 1
        let id = count
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { requests[id] = $0 }
        } onCancel: { Task { await self.cancelled() } }
    }
    private func cancelled() { cancellations += 1 }
    func finishWithoutIdentity(_ id: Int) {
        requests.removeValue(forKey: id)?.resume(returning: UsageSnapshot(weekly: UsageWindow(usedPercent: 95,
            windowDurationMins: 10080, resetsAt: Date().addingTimeInterval(86400).timeIntervalSince1970)))
    }
    func finishFailure(_ id: Int, error: any Error) {
        requests.removeValue(forKey: id)?.resume(throwing: error)
    }
    func finish(_ id: Int, used: Double = 28, error: UsageError? = nil) {
        guard let request = requests.removeValue(forKey: id) else { return }
        if let error { request.resume(throwing: error) }
        else {
            request.resume(returning: UsageSnapshot(weekly: UsageWindow(usedPercent: used,
                windowDurationMins: 10080, resetsAt: Date().addingTimeInterval(86400).timeIntervalSince1970), accountKey: "fixture-account"))
        }
    }
}

private actor DeferredLogin: UsageLoginAttempt {
    private var requests: [Int: CheckedContinuation<Void, Error>] = [:]
    private(set) var count = 0
    private(set) var cancellations = 0
    func login(openBrowser: @escaping @Sendable (URL) -> Void) async throws {
        count += 1
        let id = count
        try await withCheckedThrowingContinuation { requests[id] = $0 }
    }
    nonisolated func cancel() { Task { await self.cancelled() } }
    private func cancelled() { cancellations += 1 }
    func finish(_ id: Int, error: UsageError? = nil) {
        guard let request = requests.removeValue(forKey: id) else { return }
        if let error { request.resume(throwing: error) }
        else { request.resume() }
    }
}

private actor DeferredNotifications {
    private var pending: CheckedContinuation<Bool, Never>?
    private(set) var checks = 0
    private(set) var deliveries: [String] = []
    func authorization() async -> Bool {
        checks += 1
        return await withCheckedContinuation { pending = $0 }
    }
    func allow() { pending?.resume(returning: true); pending = nil }
    func deliver(_ body: String) { deliveries.append(body) }
}

private final class FixtureTelemetryReceiver: TokenTelemetryReceiving, @unchecked Sendable {
    private let lock = NSLock()
    private var starts: [String] = []
    private var stops = 0
    private let provider: UsageProviderKind
    private let onSamples: @Sendable ([TokenSpeedSample]) -> Void
    init(provider: UsageProviderKind = .codex, onSamples: @escaping @Sendable ([TokenSpeedSample]) -> Void) {
        self.provider = provider; self.onSamples = onSamples
    }
    var startCount: Int { lock.withLock { starts.count } }
    var scopes: [String] { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
    func start(accountKey: String) async throws -> TokenTelemetryConnection {
        lock.withLock { starts.append(accountKey) }
        let path = provider == .codex ? "traces" : provider == .antigravity ? "samples" : "logs"
        return TokenTelemetryConnection(endpoint: URL(string: "http://127.0.0.1:43199/v1/" + path)!, authorizationHeader: "Bearer fixture-ephemeral")
    }
    func stop() { lock.withLock { stops += 1 } }
    func emit(_ sample: TokenSpeedSample) { onSamples([sample]) }
}

private actor FixtureRecentSessionMonitor: CodexRecentSessionMonitoring {
    nonisolated let scopeKey = "codex-recent:" + UUID().uuidString
    private var observation: CodexRecentSessionObservation?
    private(set) var polls = 0
    private var pending: CheckedContinuation<CodexRecentSessionObservation, Error>?
    let deferred: Bool
    let createsProgressDuringPoll: Bool
    init(deferred: Bool = false, createsProgressDuringPoll: Bool = false) {
        self.deferred = deferred; self.createsProgressDuringPoll = createsProgressDuringPoll
    }
    func set(_ sample: TokenSpeedSample?, discovered: Int = 1, unsupported: Int = 0) {
        observation = CodexRecentSessionObservation(latestSample: sample, discoveredSessionCount: discovered,
            unsupportedSessionCount: unsupported, isCatchingUp: false)
    }
    func poll(now: Date) async throws -> CodexRecentSessionObservation {
        polls += 1
        if deferred { return try await withCheckedThrowingContinuation { pending = $0 } }
        if createsProgressDuringPoll {
            try await Task.sleep(for: .milliseconds(10))
            let sample = TokenSpeedSample(outputTokens: 150, durationMilliseconds: 3000, recordedAt: Date(),
                accountKey: scopeKey, requestKey: "turn-progress:fixture")!
            return CodexRecentSessionObservation(latestSample: sample, discoveredSessionCount: 1,
                unsupportedSessionCount: 0, isCatchingUp: false)
        }
        return observation ?? CodexRecentSessionObservation(latestSample: nil, discoveredSessionCount: 0,
            unsupportedSessionCount: 0, isCatchingUp: false)
    }
    func finish(_ sample: TokenSpeedSample?) {
        pending?.resume(returning: CodexRecentSessionObservation(latestSample: sample, discoveredSessionCount: 1,
            unsupportedSessionCount: 0, isCatchingUp: false)); pending = nil
    }
}

@MainActor
final class LifecycleTests: XCTestCase {
    private func defaults() -> (String, UserDefaults) {
        let id = "HappyLulu.AIUsageTests." + UUID().uuidString
        return (id, UserDefaults(suiteName: id)!)
    }
    private func eventually(_ predicate: () async -> Bool) async throws {
        let end = Date().addingTimeInterval(3)
        while !(await predicate()) {
            guard Date() < end else { XCTFail("Condition did not arrive"); return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    func testLoginKeepsPluginBusyThroughFollowUpRefresh() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let login = DeferredLogin(), provider = DeferredProvider(loginAttempt: login)
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider })
        let controller: any PluginController = model
        defer { model.stop() }
        model.setEnabled(true); model.start()
        try await eventually { await provider.count == 1 }; await provider.finish(1)
        try await eventually { !controller.isRunning }
        model.login()
        XCTAssertTrue(controller.isRunning, "The host must defer automatic updates while browser login is pending")
        try await eventually { await login.count == 1 }
        model.refreshData(); model.login()
        await login.finish(1)
        try await eventually { await provider.count == 2 }
        XCTAssertFalse(model.isLoggingIn)
        XCTAssertTrue(controller.isRunning, "The post-login refresh must remain protected")
        let loginCount = await login.count
        XCTAssertEqual(loginCount, 1)
        await provider.finish(2)
        try await eventually { !controller.isRunning }
    }

    func testFailedLoginReleasesPluginBusyState() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let login = DeferredLogin(), provider = DeferredProvider(loginAttempt: login)
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider })
        defer { model.stop() }
        model.setEnabled(true); model.start()
        try await eventually { await provider.count == 1 }; await provider.finish(1)
        try await eventually { !model.isRunning }
        model.login()
        XCTAssertTrue(model.isRunning)
        try await eventually { await login.count == 1 }; await login.finish(1, error: .loginFailed)
        try await eventually { !model.isLoggingIn }
        XCTAssertFalse(model.isRunning)
        XCTAssertNotNil(model.message)
    }

    func testCancelledLoginCannotClearNewLoginBusyState() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let login = DeferredLogin(), provider = DeferredProvider(loginAttempt: login)
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider })
        defer { model.stop() }
        model.setEnabled(true); model.start()
        try await eventually { await provider.count == 1 }; await provider.finish(1)
        try await eventually { !model.isRunning }
        model.login()
        try await eventually { await login.count == 1 }
        model.cancelLogin()
        XCTAssertFalse(model.isRunning)
        model.login()
        try await eventually { await login.count == 2 }
        await login.finish(1)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(model.isLoggingIn)
        XCTAssertTrue(model.isRunning, "A cancelled attempt must not release the new login's update protection")
        await login.finish(2, error: .loginFailed)
        try await eventually { !model.isLoggingIn }
        XCTAssertFalse(model.isRunning)
    }

    func testDisablingDuringLoginReleasesBusyStateAndIgnoresLateCompletion() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let login = DeferredLogin(), provider = DeferredProvider(loginAttempt: login)
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider })
        model.setEnabled(true); model.start()
        try await eventually { await provider.count == 1 }; await provider.finish(1)
        try await eventually { !model.isRunning }
        model.login()
        try await eventually { await login.count == 1 }
        model.setEnabled(false)
        XCTAssertFalse(model.isRunning)
        XCTAssertFalse(model.isLoggingIn)
        try await eventually { await login.cancellations == 1 }
        await login.finish(1)
        try await Task.sleep(for: .milliseconds(30))
        let fetchCount = await provider.count
        XCTAssertEqual(fetchCount, 1)
        XCTAssertNil(model.snapshot)
    }

    func testNotificationRechecksThresholdAfterPermissionLookup() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        var preferences = Preferences(); preferences.notificationsEnabled = true; preferences.notificationThreshold = 30
        defaults.set(try JSONEncoder().encode(preferences), forKey: "HappyLuluAIUsage.preferences.v1")
        let provider = DeferredProvider()
        let notifications = DeferredNotifications()
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider },
            notificationAuthorization: { await notifications.authorization() },
            notificationDelivery: { _, _, body in await notifications.deliver(body) })
        model.setEnabled(true); model.start()
        try await eventually { await provider.count == 1 }; await provider.finish(1, used: 75)
        try await eventually { await notifications.checks == 1 }
        model.updatePreferences { $0.notificationThreshold = 10 }
        await notifications.allow()
        try await eventually { !model.isRunning }
        let deliveries = await notifications.deliveries
        XCTAssertTrue(deliveries.isEmpty, "25% remaining must not trigger the newly selected 10% threshold: \(deliveries)")
        model.stop()
    }

    func testDisabledDoesNotQueryAndStartIsIdempotent() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let provider = DeferredProvider()
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider })
        model.start(); model.refreshData()
        let before = await provider.count
        XCTAssertEqual(before, 0)
        XCTAssertNil(model.menuBarItem)
        model.setEnabled(true); model.start(); model.start(); model.refreshData()
        try await eventually { await provider.count == 1 }
        await provider.finish(1)
        try await eventually { !model.isRunning }
        XCTAssertEqual(model.menuBarItem?.title, "Fixture 72%")
        model.stop()
    }
    func testHideCancelsAndLateResultCannotRestoreDisplayOrHistory() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let provider = DeferredProvider()
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider })
        model.setEnabled(true); model.start()
        try await eventually { await provider.count == 1 }
        model.setEnabled(false)
        try await eventually { await provider.cancellations == 1 }
        XCTAssertFalse(model.isRunning)
        XCTAssertNil(model.menuBarItem)
        await provider.finish(1)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(model.snapshot)
        XCTAssertNil(defaults.data(forKey: "HappyLuluAIUsage.history.v1"))
    }
    func testOldGenerationCannotOverwriteReenabledRequest() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let provider = DeferredProvider()
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider })
        model.setEnabled(true); model.start()
        try await eventually { await provider.count == 1 }
        model.setEnabled(false); model.setEnabled(true); model.start()
        try await eventually { await provider.count == 2 }
        await provider.finish(1, used: 99)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(model.isRunning)
        XCTAssertNil(model.snapshot)
        await provider.finish(2, used: 20)
        try await eventually { !model.isRunning }
        XCTAssertEqual(model.snapshot?.weekly.remainingPercent, 80)
        model.stop()
    }
    func testTransientErrorRetainsStaleValueButSignoutClearsIt() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let provider = DeferredProvider()
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider })
        model.setEnabled(true); model.start()
        try await eventually { await provider.count == 1 }; await provider.finish(1)
        try await eventually { !model.isRunning }
        model.refreshData()
        try await eventually { await provider.count == 2 }; await provider.finish(2, error: .timeout)
        try await eventually { !model.isRunning }
        XCTAssertEqual(model.menuBarItem?.title, "Fixture 72% ·")
        XCTAssertNotNil(model.snapshot)
        model.refreshData()
        try await eventually { await provider.count == 3 }; await provider.finish(3, error: .notLoggedIn)
        try await eventually { !model.isRunning }
        XCTAssertNil(model.snapshot)
        XCTAssertNil(defaults.data(forKey: "HappyLuluAIUsage.history.v1"))
        XCTAssertEqual(model.menuBarItem?.title, "Fixture —")
        model.stop()
    }
    func testPercentageOnlyLabelKeepsProviderAndMeaningForAccessibility() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let provider = DeferredProvider()
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, localize: { _, en in en }, providerFactory: { _ in provider })
        model.updatePreferences { $0.labelFormat = .percentage }
        model.setEnabled(true); model.start()
        try await eventually { await provider.count == 1 }; await provider.finish(1)
        try await eventually { !model.isRunning }
        XCTAssertEqual(model.menuBarItem?.title, "72%")
        XCTAssertEqual(model.menuBarItem?.accessibilityLabel, "Fixture weekly remaining 72%")
        model.refreshData()
        try await eventually { await provider.count == 2 }; await provider.finish(2, error: .timeout)
        try await eventually { !model.isRunning }
        XCTAssertTrue(model.menuBarItem?.accessibilityLabel.contains("previous reading") == true)
        model.stop()
    }

    func testIconLabelUsesCachedImageAndPreservesAccessibilityAndStaleValue() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let provider = DeferredProvider()
        let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII=")!
        var iconReads = 0
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, localize: { _, en in en }, providerFactory: { _ in provider },
            iconProvider: { iconReads += 1; return image })
        defer { model.stop() }
        model.updatePreferences { $0.labelFormat = .icon }
        XCTAssertEqual(model.menuBarPreview.title, "—")
        XCTAssertEqual(model.menuBarPreview.iconPNG, image)
        XCTAssertNil(model.menuBarItem)
        model.setEnabled(true); model.start()
        try await eventually { await provider.count == 1 }; await provider.finish(1)
        try await eventually { !model.isRunning }
        XCTAssertEqual(model.menuBarItem?.title, "72%")
        XCTAssertEqual(model.menuBarItem?.iconPNG, image)
        XCTAssertEqual(model.menuBarItem?.iconIsTemplate, true)
        XCTAssertEqual(model.menuBarItem?.accessibilityLabel, "Fixture weekly remaining 72%")
        model.refreshData()
        try await eventually { await provider.count == 2 }; await provider.finish(2, error: .timeout)
        try await eventually { !model.isRunning }
        XCTAssertEqual(model.menuBarItem?.title, "72% ·")
        XCTAssertTrue(model.menuBarItem?.accessibilityLabel.contains("previous reading") == true)
        model.updatePreferences { $0.labelFormat = .percentage }
        XCTAssertEqual(model.menuBarItem?.title, "72% ·")
        XCTAssertNil(model.menuBarItem?.iconPNG)
        XCTAssertEqual(model.menuBarItem?.iconIsTemplate, false)
        model.updatePreferences { $0.labelFormat = .named }
        XCTAssertEqual(model.menuBarItem?.title, "Fixture 72% ·")
        XCTAssertNil(model.menuBarItem?.iconPNG)
        model.updatePreferences { $0.labelFormat = .icon }
        XCTAssertEqual(model.menuBarItem?.iconPNG, image)
        XCTAssertEqual(iconReads, 1)
        model.refreshData()
        try await eventually { await provider.count == 3 }; await provider.finish(3, error: .notLoggedIn)
        try await eventually { !model.isRunning }
        XCTAssertEqual(model.menuBarItem?.title, "—")
        XCTAssertEqual(model.menuBarItem?.iconPNG, image)
    }

    func testMissingOrInvalidIconFallsBackToNameWithoutChangingSavedChoice() async throws {
        for icon in [nil, Data("invalid image".utf8)] as [Data?] {
            let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
            let provider = DeferredProvider()
            let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider }, iconProvider: { icon })
            defer { model.stop() }
            model.updatePreferences { $0.labelFormat = .icon; $0.refreshMinutes = 15 }
            XCTAssertEqual(model.menuBarPreview.title, "Fixture —")
            model.setEnabled(true); model.start()
            try await eventually { await provider.count == 1 }; await provider.finish(1)
            try await eventually { !model.isRunning }
            XCTAssertEqual(model.menuBarItem?.title, "Fixture 72%")
            XCTAssertNil(model.menuBarItem?.iconPNG)
            XCTAssertEqual(model.preferences.labelFormat, .icon)
            let restored = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider }, iconProvider: { nil })
            XCTAssertEqual(restored.preferences.labelFormat, .icon)
            XCTAssertEqual(restored.preferences.refreshMinutes, 15)
        }
    }

    func testPreferencesPersistWithoutTouchingAttendanceOrCodexUsageSettings() {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        defaults.set("preserved", forKey: "preferences")
        defaults.set("attendance", forKey: "unrelated")
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() })
        model.updatePreferences { $0.refreshMinutes = 10; $0.labelFormat = .percentage }
        let restored = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() })
        XCTAssertEqual(restored.preferences.refreshMinutes, 10)
        XCTAssertEqual(restored.preferences.labelFormat, .percentage)
        XCTAssertFalse(restored.enabled)
        XCTAssertNil(restored.menuBarItem)
        XCTAssertEqual(defaults.string(forKey: "preferences"), "preserved")
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "attendance")
    }
    func testChangingExecutableCancelsPreviousProviderGeneration() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let provider = DeferredProvider()
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider })
        model.setEnabled(true); model.start()
        try await eventually { await provider.count == 1 }
        model.updatePreferences { $0.cliPath = "/fixture/new-codex" }
        try await eventually { await provider.count == 2 }
        await provider.finish(1, used: 99); await provider.finish(2, used: 10)
        try await eventually { !model.isRunning }
        XCTAssertEqual(model.snapshot?.weekly.remainingPercent, 90)
        XCTAssertEqual(model.preferences.cliPath, "/fixture/new-codex")
        model.stop()
    }
    func testProfileSwitchCancelsOldRequestAndKeepsHistorySeparated() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let first = DeferredProvider(), second = DeferredProvider()
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { $0.selectedProfile.name == "Work" ? second : first })
        defer { model.stop() }
        model.setEnabled(true); model.start()
        try await eventually { await first.count == 1 }
        let workID = model.addProfile(provider: .codex, name: "Work")
        try await eventually { await second.count == 1 }
        await first.finish(1, used: 99)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(model.snapshot)
        await second.finish(1, used: 10)
        try await eventually { !model.isRunning }
        XCTAssertEqual(model.snapshot?.weekly.remainingPercent, 90)
        XCTAssertNotNil(defaults.data(forKey: "HappyLuluAIUsage.history.v1." + workID))
        XCTAssertNil(defaults.data(forKey: "HappyLuluAIUsage.history.v1"))
        model.selectProfile(UsageProfile.defaultCodexID)
        try await eventually { await first.count == 2 }
        await first.finish(2, used: 40)
        try await eventually { !model.isRunning }
        XCTAssertEqual(model.snapshot?.weekly.remainingPercent, 60)
        XCTAssertNotNil(defaults.data(forKey: "HappyLuluAIUsage.history.v1"))
        model.removeSelectedProfile()
        XCTAssertEqual(model.preferences.selectedProfileID, workID)
        await second.finish(2)
    }

    func testAntigravityProfilesDoNotPretendToBeIndependentAccounts() {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() })
        let first = model.addProfile(provider: .antigravity, name: "Current")
        let second = model.addProfile(provider: .antigravity, name: "Other")
        XCTAssertEqual(first, second)
        XCTAssertEqual(model.preferences.profiles.filter { $0.provider == .antigravity }.count, 1)
    }

    func testChangingAntigravityCLIConsentCancelsPreviousRead() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let provider = DeferredProvider()
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider })
        defer { model.stop() }
        model.addProfile(provider: .antigravity)
        model.setEnabled(true); model.start()
        try await eventually { await provider.count == 1 }
        model.updateSelectedProfile { $0.allowAntigravityCLI = true }
        try await eventually { await provider.count == 2 }
        await provider.finish(1, used: 99)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(model.snapshot)
        await provider.finishWithoutIdentity(2)
        try await eventually { !model.isRunning }
        XCTAssertTrue(model.selectedProfile.allowAntigravityCLI)
        XCTAssertEqual(model.snapshot?.weekly.remainingPercent, 5)
        XCTAssertNil(model.analysis.hour)
    }

    func testLegacyUnsupportedProfilePreservesSettingsWithoutReadingOrStartingMeasurement() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        var saved = Preferences()
        saved.profiles.append(UsageProfile(id: "legacy", name: "Legacy", provider: .claude,
            cliPath: "/fixture/legacy", configDirectory: "/fixture/legacy-home"))
        saved.selectedProfileID = "legacy"
        defaults.set(try JSONEncoder().encode(saved), forKey: "HappyLuluAIUsage.preferences.v1")
        let provider = DeferredProvider()
        var receiverCreated = false
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() },
            providerFactory: { _ in provider }, telemetryReceiverFactory: { kind, callback in
                receiverCreated = true
                return FixtureTelemetryReceiver(provider: kind, onSamples: callback)
            })
        defer { model.stop() }
        model.setEnabled(true); model.start(); model.startTokenMeasurement()
        try await Task.sleep(for: .milliseconds(30))
        let reads = await provider.count
        XCTAssertEqual(reads, 0)
        XCTAssertFalse(model.canStartTokenMeasurement)
        XCTAssertFalse(receiverCreated)
        XCTAssertNil(model.tokenTelemetryCommand)
        XCTAssertNil(model.currentTokenSpeedSample)
        XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.preferences, saved)
        XCTAssertNotNil(model.message)
        model.addProfile(provider: .claude)
        XCTAssertEqual(model.preferences.profiles.count, 2)
    }

    func testUnidentifiedReadingDoesNotPersistHistoryOrSendAccountAlerts() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        var saved = Preferences(); saved.notificationsEnabled = true
        defaults.set(try JSONEncoder().encode(saved), forKey: "HappyLuluAIUsage.preferences.v1")
        let provider = DeferredProvider()
        var notifications = 0
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider },
            notificationAuthorization: { true }, notificationDelivery: { _, _, _ in notifications += 1 })
        model.setEnabled(true); model.start()
        defer { model.stop() }
        try await eventually { await provider.count == 1 }; await provider.finishWithoutIdentity(1)
        try await eventually { !model.isRunning }
        XCTAssertEqual(model.snapshot?.weekly.remainingPercent, 5)
        XCTAssertNil(defaults.data(forKey: "HappyLuluAIUsage.history.v1"))
        XCTAssertNil(model.analysis.hour)
        XCTAssertEqual(notifications, 0)
    }

    func testConnectionPathsExpandTildeAndPreserveDefaultAndAbsolutePaths() {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() })
        for kind in UsageProviderKind.allCases {
            model.addProfile(provider: kind)
            model.setConfigDirectory("  ~/HappyLulu-fixture/usage.json  ")
            let expected = ("~/HappyLulu-fixture/usage.json" as NSString).expandingTildeInPath
            XCTAssertEqual(model.selectedProfile.configDirectory, expected)
            XCTAssertTrue(model.selectedProfile.configDirectory.hasPrefix("/"))
            model.setConfigDirectory("/fixture/account-or-report")
            XCTAssertEqual(model.selectedProfile.configDirectory, "/fixture/account-or-report")
            model.setConfigDirectory("")
            XCTAssertEqual(model.selectedProfile.configDirectory, "")
        }
    }

    func testCodexAndAntigravityMeasureOnlyTheirProfileConnectionScope() async throws {
        for kind in [UsageProviderKind.codex, .antigravity] {
            let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
            let provider = DeferredProvider()
            var receiver: FixtureTelemetryReceiver?
            let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider }, telemetryReceiverFactory: { selected, callback in
                XCTAssertEqual(selected, kind)
                let value = FixtureTelemetryReceiver(provider: selected, onSamples: callback); receiver = value; return value
            })
            defer { model.stop() }
            if kind == .antigravity { model.addProfile(provider: .antigravity) }
            else { model.setTokenMeasurementSource(.newSession) }
            model.setEnabled(true); model.start()
            model.startTokenMeasurement()
            try await eventually { model.tokenTelemetryConnection != nil }
            let scope = try XCTUnwrap(receiver?.scopes.first)
            XCTAssertTrue(scope.hasPrefix(kind == .codex ? "codex-profile:" : "antigravity:"))
            XCTAssertFalse(defaults.dictionaryRepresentation().description.contains("fixture-ephemeral"))
            receiver?.emit(TokenSpeedSample(outputTokens: 150, durationMilliseconds: 3000, recordedAt: Date(), accountKey: "other-scope", requestKey: "wrong-scope")!)
            receiver?.emit(TokenSpeedSample(outputTokens: 150, durationMilliseconds: 3000, recordedAt: Date().addingTimeInterval(-901), accountKey: scope, requestKey: "stale-request")!)
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertNil(model.currentTokenSpeedSample)
            receiver?.emit(TokenSpeedSample(outputTokens: 150, durationMilliseconds: 3000, recordedAt: Date(), accountKey: scope, requestKey: "measured-request")!)
            try await eventually { model.currentTokenSpeedSample?.tokensPerSecond == 50 }
            model.addProfile(provider: .codex, name: "Other Codex")
            XCTAssertNil(model.currentTokenSpeedSample)
            XCTAssertNil(model.tokenTelemetryConnection)
            receiver?.emit(TokenSpeedSample(outputTokens: 900, durationMilliseconds: 1000, recordedAt: Date(), accountKey: scope, requestKey: "late-request")!)
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertNil(model.currentTokenSpeedSample)
            try await eventually { await provider.count >= 2 }
            await provider.finish(1); await provider.finish(2)
        }
    }

    func testCodexLaunchCommandUsesSelectedHomeAndClearsRustOTLPHeaderAndCompressionOverrides() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("HappyLulu-codex-command-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let executable = fixture.appendingPathComponent("Codex fixture's executable")
        try Data(#"""
#!/usr/bin/python3
import json, os, sys
print(json.dumps({"arguments": sys.argv[1:], "home": os.environ.get("CODEX_HOME"), "headers": os.environ.get("OTEL_EXPORTER_OTLP_HEADERS"), "traceHeaders": os.environ.get("OTEL_EXPORTER_OTLP_TRACES_HEADERS"), "compression": os.environ.get("OTEL_EXPORTER_OTLP_COMPRESSION"), "traceCompression": os.environ.get("OTEL_EXPORTER_OTLP_TRACES_COMPRESSION")}))
"""#.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let provider = DeferredProvider()
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider }, telemetryReceiverFactory: { FixtureTelemetryReceiver(provider: $0, onSamples: $1) })
        defer { model.stop() }
        model.updateSelectedProfile { $0.cliPath = executable.path; $0.configDirectory = "/fixture/Codex account's home" }
        model.setTokenMeasurementSource(.newSession)
        model.setEnabled(true); model.start(); model.startTokenMeasurement()
        try await eventually { model.tokenTelemetryCommand != nil }
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh"); process.arguments = ["-c", try XCTUnwrap(model.tokenTelemetryCommand)]
        process.environment = ["PATH": "/usr/bin:/bin", "OTEL_EXPORTER_OTLP_HEADERS": "company=synthetic", "OTEL_EXPORTER_OTLP_TRACES_HEADERS": "Authorization=synthetic-old", "OTEL_EXPORTER_OTLP_COMPRESSION": "gzip", "OTEL_EXPORTER_OTLP_TRACES_COMPRESSION": "gzip"]
        process.standardOutput = output; process.standardError = Pipe()
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: output.fileHandleForReading.readDataToEndOfFile()) as? [String: Any])
        XCTAssertEqual(value["home"] as? String, "/fixture/Codex account's home")
        for key in ["headers", "traceHeaders", "compression", "traceCompression"] { XCTAssertTrue(value[key] is NSNull, key) }
        let arguments = try XCTUnwrap(value["arguments"] as? [String])
        XCTAssertTrue(arguments.contains("otel.exporter=\"none\""))
        XCTAssertTrue(arguments.contains("otel.metrics_exporter=\"none\""))
        XCTAssertTrue(arguments.contains("otel.log_user_prompt=false"))
        let trace = try XCTUnwrap(arguments.first(where: { $0.hasPrefix("otel.trace_exporter=") }))
        XCTAssertTrue(trace.contains("endpoint=\"http://127.0.0.1:43199/v1/traces\""))
        XCTAssertTrue(trace.contains("protocol=\"json\""))
        XCTAssertTrue(trace.contains("Authorization=\"Bearer fixture-ephemeral\""))
        try await eventually { await provider.count == 1 }; await provider.finish(1)
    }

    func testAntigravityLaunchCommandKeepsPromptLiteralAndCredentialsOnlyOnBridge() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("HappyLulu-agy-command-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let executable = fixture.appendingPathComponent("agy fixture's executable"), bridge = fixture.appendingPathComponent("bridge fixture's executable")
        try Data(#"""
#!/usr/bin/python3
import json, os, sys
print(json.dumps({"arguments": sys.argv[1:], "auth_in_agy": os.environ.get("HAPPY_LULU_TOKEN_AUTH")}))
"""#.utf8).write(to: executable)
        try Data(#"""
#!/usr/bin/python3
import json, os, sys
print(json.dumps({"arguments": sys.argv[1:], "endpoint": os.environ.get("HAPPY_LULU_TOKEN_ENDPOINT"), "auth": os.environ.get("HAPPY_LULU_TOKEN_AUTH"), "scope": os.environ.get("HAPPY_LULU_TOKEN_SCOPE"), "input": json.loads(sys.stdin.read())}))
"""#.utf8).write(to: bridge)
        for path in [executable, bridge] { try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path) }
        let provider = DeferredProvider()
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider }, telemetryReceiverFactory: { FixtureTelemetryReceiver(provider: $0, onSamples: $1) }, bridgeExecutablePath: bridge.path)
        defer { model.stop() }
        model.addProfile(provider: .antigravity); model.updateSelectedProfile { $0.cliPath = executable.path }
        model.setEnabled(true); model.start(); model.startTokenMeasurement()
        try await eventually { model.tokenTelemetryCommand != nil }
        let process = Process(), output = Pipe(), input = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh"); process.arguments = ["-c", try XCTUnwrap(model.tokenTelemetryCommand)]
        process.environment = ["PATH": "/usr/bin:/bin"]
        process.standardOutput = output; process.standardError = Pipe(); process.standardInput = input
        try process.run()
        let prompt = "literal '$()' task"
        input.fileHandleForWriting.write(Data((prompt + "\n").utf8)); try input.fileHandleForWriting.close()
        process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        let raw = try XCTUnwrap(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8))
        let json = Data(raw.dropFirst("Antigravity prompt: ".count).utf8)
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        XCTAssertEqual(value["endpoint"] as? String, "http://127.0.0.1:43199/v1/samples")
        XCTAssertEqual(value["auth"] as? String, "Bearer fixture-ephemeral")
        XCTAssertTrue((value["scope"] as? String)?.hasPrefix("antigravity:") == true)
        XCTAssertEqual(value["arguments"] as? [String], ["--token-speed-bridge", "antigravity"])
        let upstream = try XCTUnwrap(value["input"] as? [String: Any])
        XCTAssertTrue(upstream["auth_in_agy"] is NSNull)
        XCTAssertEqual(upstream["arguments"] as? [String], ["-p", prompt, "--output-format", "stream-json"])
        try await eventually { await provider.count == 1 }; await provider.finishWithoutIdentity(1)
    }

    func testCodexSelectedSessionFileMeasuresWithoutQuotaAndStopsOnProfileSwitch() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let fixture = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("HappyLulu-session-ui-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let path = fixture.appendingPathComponent("selected.jsonl").resolvingSymlinksInPath()
        let session = UUID().uuidString
        let completed = Int64(Date().addingTimeInterval(-1).timeIntervalSince1970 * 1000)
        func line(_ value: [String: Any]) throws -> Data { var data = try JSONSerialization.data(withJSONObject: value); data.append(10); return data }
        let header = try line(["type": "session_meta", "payload": ["id": session, "history_mode": "paginated"]])
        let item = try line(["type": "event_msg", "payload": ["type": "item_completed", "thread_id": session, "turn_id": "fixture-turn",
            "item": ["type": "AgentMessage", "id": "fixture-message", "content": "PRIVATE RESPONSE"],
            "content_token_count": 150, "started_at_ms": completed - 3000, "completed_at_ms": completed]])
        try (header + item).write(to: path)
        let provider = DeferredProvider()
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider })
        defer { model.stop() }
        model.setTokenMeasurementSource(.codexSessionFile)
        model.setCodexSessionFile(path.path)
        model.startTokenMeasurement()
        XCTAssertFalse(model.isObservingCodexSession)
        model.setEnabled(true); model.start(); model.startTokenMeasurement()
        try await eventually { model.currentTokenSpeedSample?.tokensPerSecond == 50 }
        XCTAssertNil(model.tokenTelemetryMessage)
        XCTAssertTrue(model.isObservingCodexSession)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.tokenTelemetryConnection)
        XCTAssertTrue(model.currentTokenSpeedSample?.accountKey.hasPrefix("codex-session:") == true)
        XCTAssertTrue(model.tokenSpeedDisplayTitle.contains("메시지 평균"))
        XCTAssertEqual(try Data(contentsOf: path), header + item)
        try header.write(to: path)
        try await eventually { model.currentTokenSpeedSample == nil }
        model.addProfile(provider: .antigravity)
        XCTAssertFalse(model.isObservingCodexSession)
        XCTAssertEqual(model.codexSessionFilePath, "")
        XCTAssertEqual(model.tokenMeasurementSource, .newSession)
        try await eventually { await provider.count >= 2 }; await provider.finish(1); await provider.finish(2)
    }

    func testCodexAutomaticallyMeasuresRecentLocalSessionsWithoutQuotaOrLaunchCommand() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let provider = DeferredProvider(), monitor = FixtureRecentSessionMonitor()
        let sample = TokenSpeedSample(outputTokens: 150, durationMilliseconds: 3000, recordedAt: Date(),
            accountKey: monitor.scopeKey, requestKey: "turn:fixture")!
        await monitor.set(sample)
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in monitor }, providerFactory: { _ in provider })
        defer { model.stop() }
        model.setEnabled(true); model.start()
        try await eventually { model.currentTokenSpeedSample?.tokensPerSecond == 50 }
        XCTAssertEqual(model.tokenMeasurementSource, .codexRecentSessions)
        XCTAssertTrue(model.isObservingCodexSession)
        XCTAssertNil(model.snapshot)
        XCTAssertNil(model.tokenTelemetryCommand)
        XCTAssertTrue(model.menuBarPreview.title.contains("50.0 tok/s"))
        XCTAssertTrue(model.tokenSpeedDisplayTitle.contains("턴 평균"))
        XCTAssertEqual(model.recentCodexSessionCount, 1)
        model.setEnabled(false)
        XCTAssertNil(model.currentTokenSpeedSample)
        XCTAssertFalse(model.isObservingCodexSession)
        try await eventually { await provider.count == 1 }; await provider.finish(1)
    }

    func testCodexAutomaticMeasurementIgnoresLateResultsAfterProfileSwitch() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let provider = DeferredProvider(), monitor = FixtureRecentSessionMonitor(deferred: true)
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in monitor }, providerFactory: { _ in provider })
        defer { model.stop() }
        model.setEnabled(true); model.start()
        try await eventually { await monitor.polls == 1 }
        model.addProfile(provider: .antigravity)
        let late = TokenSpeedSample(outputTokens: 150, durationMilliseconds: 3000, recordedAt: Date(),
            accountKey: monitor.scopeKey, requestKey: "turn:late")!
        await monitor.finish(late)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(model.currentTokenSpeedSample)
        XCTAssertFalse(model.isObservingCodexSession)
        try await eventually { await provider.count >= 2 }; await provider.finish(1); await provider.finish(2)
    }

    func testCodexAutomaticMeasurementRejectsStaleValuesAndReportsMissingFields() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let provider = DeferredProvider(), monitor = FixtureRecentSessionMonitor()
        let stale = TokenSpeedSample(outputTokens: 150, durationMilliseconds: 3000, recordedAt: Date().addingTimeInterval(-901),
            accountKey: monitor.scopeKey, requestKey: "turn:stale")!
        await monitor.set(stale, discovered: 2, unsupported: 1)
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in monitor }, providerFactory: { _ in provider })
        defer { model.stop() }
        model.setEnabled(true); model.start()
        try await eventually { model.recentCodexSessionCount == 2 }
        XCTAssertNil(model.currentTokenSpeedSample)
        XCTAssertEqual(model.unsupportedCodexSessionCount, 1)
        XCTAssertFalse(model.menuBarPreview.title.contains("tok/s"))
        try await eventually { await provider.count == 1 }; await provider.finish(1)
    }

    func testCodexAutomaticMeasurementStopRejectsLateResultAndKeepsManualSource() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let provider = DeferredProvider(), monitor = FixtureRecentSessionMonitor(deferred: true)
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { home in
            XCTAssertEqual(home, "/fixture/selected-codex-home")
            return monitor
        }, providerFactory: { _ in provider })
        defer { model.stop() }
        model.setConfigDirectory("/fixture/selected-codex-home")
        model.setEnabled(true); model.start()
        try await eventually { await monitor.polls == 1 }
        model.setTokenMeasurementSource(.newSession)
        let sample = TokenSpeedSample(outputTokens: 150, durationMilliseconds: 3000, recordedAt: Date(),
            accountKey: monitor.scopeKey, requestKey: "turn:late")!
        await monitor.finish(sample)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(model.currentTokenSpeedSample)
        XCTAssertFalse(model.isObservingCodexSession)
        XCTAssertEqual(model.tokenMeasurementSource, .newSession)
        XCTAssertTrue(model.canStartTokenMeasurement)
        try await eventually { await provider.count == 1 }; await provider.finish(1)
    }

    func testCodexAutomaticMeasurementShowsNoNumberWhenNoSessionHasMeasurements() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let provider = DeferredProvider(), monitor = FixtureRecentSessionMonitor()
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in monitor }, providerFactory: { _ in provider })
        defer { model.stop() }
        model.setEnabled(true); model.start()
        try await eventually { model.isObservingCodexSession }
        XCTAssertNil(model.currentTokenSpeedSample)
        XCTAssertEqual(model.recentCodexSessionCount, 0)
        XCTAssertFalse(model.menuBarPreview.title.contains("tok/s"))
        XCTAssertNil(defaults.data(forKey: "HappyLuluAIUsage.preferences.v1"))
        model.stopTokenMeasurement()
        XCTAssertFalse(model.isObservingCodexSession)
        XCTAssertFalse(model.isTokenMeasurementStarting)
        XCTAssertTrue(model.canStartTokenMeasurement)
        try await eventually { await provider.count == 1 }; await provider.finish(1)
    }

    func testCodexAutomaticMeasurementAcceptsProgressRecordedDuringAsynchronousPoll() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let provider = DeferredProvider(), monitor = FixtureRecentSessionMonitor(createsProgressDuringPoll: true)
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in monitor }, providerFactory: { _ in provider })
        defer { model.stop() }
        model.setEnabled(true); model.start()
        try await eventually { model.currentTokenSpeedSample?.tokensPerSecond == 50 }
        XCTAssertTrue(model.tokenSpeedDisplayTitle.contains("진행 턴 평균"))
        XCTAssertTrue(model.tokenSpeedDisplayTitle.contains("마지막 기록까지"))
        XCTAssertTrue(model.menuBarPreview.accessibilityLabel.contains("50.0 tok/s"))
        try await eventually { await provider.count == 1 }; await provider.finish(1)
    }

    func testCodexSelectedSessionAppliesCorrectedTurnSampleAtSameCompletionTime() async throws {
        let (id, defaults) = defaults(); defer { defaults.removePersistentDomain(forName: id) }
        let fixture = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("HappyLulu-session-correction-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let path = fixture.appendingPathComponent("selected.jsonl").resolvingSymlinksInPath()
        let session = UUID().uuidString
        let completed = Date().addingTimeInterval(-1), firstUsage = completed.addingTimeInterval(-1)
        func line(_ type: String, _ payload: [String: Any], at date: Date) throws -> Data {
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var data = try JSONSerialization.data(withJSONObject: ["type": type, "timestamp": formatter.string(from: date), "payload": payload])
            data.append(10); return data
        }
        func usage(_ tokens: Int, response: String, turn: String = "fixture-turn", at date: Date) throws -> Data {
            try line("token_usage_record", ["thread_id": session, "turn_id": turn, "response_id": response,
                "session_id": session, "root_turn_id": turn, "turn_token_usage": ["output_tokens": tokens]], at: date)
        }
        var initial = try line("session_meta", ["id": session, "history_mode": "paginated"], at: completed)
        initial.append(try usage(150, response: "first", at: firstUsage))
        initial.append(try line("event_msg", ["type": "task_complete", "turn_id": "fixture-turn", "duration_ms": 3000], at: completed))
        try initial.write(to: path)
        let provider = DeferredProvider()
        let model = AIUsageModel(defaults: defaults, recentSessionMonitorFactory: { _ in FixtureRecentSessionMonitor() }, providerFactory: { _ in provider })
        defer { model.stop() }
        model.setTokenMeasurementSource(.codexSessionFile); model.setCodexSessionFile(path.path)
        model.setEnabled(true); model.start(); model.startTokenMeasurement()
        try await eventually { model.currentTokenSpeedSample?.tokensPerSecond == 50 }
        let old = try XCTUnwrap(model.currentTokenSpeedSample)
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd(); try handle.write(contentsOf: usage(300, response: "late", at: completed)); try handle.close()
        try await eventually { model.currentTokenSpeedSample?.tokensPerSecond == 100 }
        XCTAssertEqual(model.currentTokenSpeedSample?.requestKey, old.requestKey)
        XCTAssertEqual(model.currentTokenSpeedSample?.recordedAt, old.recordedAt)
        let progressDate = Date().addingTimeInterval(-0.1)
        let progressHandle = try FileHandle(forWritingTo: path)
        try progressHandle.seekToEnd()
        try progressHandle.write(contentsOf: line("event_msg", ["type": "task_started", "turn_id": "abort-turn"], at: progressDate.addingTimeInterval(-3)))
        try progressHandle.write(contentsOf: usage(150, response: "progress", turn: "abort-turn", at: progressDate))
        try progressHandle.close()
        try await eventually { model.currentTokenSpeedSample?.requestKey.hasPrefix("turn-progress:") == true }
        let abortedHandle = try FileHandle(forWritingTo: path)
        try abortedHandle.seekToEnd()
        try abortedHandle.write(contentsOf: line("event_msg", ["type": "turn_aborted", "turn_id": "abort-turn"], at: Date().addingTimeInterval(-0.1)))
        try abortedHandle.close()
        try await eventually { model.currentTokenSpeedSample == nil }
        XCTAssertFalse(model.menuBarPreview.title.contains("tok/s"))
        try await eventually { await provider.count == 1 }; await provider.finish(1)
    }

}
