import AppKit
import Combine
import UserNotifications
import AIUsagePlugin
import AppPluginCore
import AppPluginHost

@MainActor
public final class AIUsageModel: ObservableObject, PluginController, PluginMenuBarProviding {
    public let descriptor = PluginDescriptor(id: AIUsageModule.id, name: "AI Usage")
    @Published public private(set) var enabled = false
    @Published public private(set) var preferences: Preferences
    @Published public private(set) var snapshot: UsageSnapshot?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var isLoggingIn = false
    // The host must defer automatic updates during both requests and browser sign-in.
    public var isRunning: Bool { isRefreshing || isLoggingIn }
    @Published public private(set) var message: String?
    @Published private var history = UsageHistory()
    public var changes: AnyPublisher<Void, Never> { objectWillChange.map { _ in () }.eraseToAnyPublisher() }
    private let defaults: UserDefaults
    private let localize: PluginLocalizer
    private let notificationAuthorization: @MainActor @Sendable () async -> Bool
    private let notificationDelivery: @MainActor @Sendable (String, String, String) async throws -> Void
    private let providerFactory: @Sendable (Preferences) -> any UsageProvider
    public let providerRegistry: UsageProviderRegistry
    @Published public private(set) var profileSettings: UsageProfileSettings
    private let iconProvider: @MainActor () -> Data?
    private lazy var cachedIconPNG: Data? = iconProvider().flatMap { NSImage(data: $0) == nil ? nil : $0 }
    private var active = false
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var task: Task<Void, Never>?
    private var loginTask: Task<Void, Never>?
    private var loginAttempt: (any UsageLoginAttempt)?
    private var generation = 0
    private var failed = false
    private var alertGate = LowUsageAlertGate()
    private var historyWritable = true
    private var notificationsWritable = true
    private var releasedPreferences: ReleasedUsagePreferences.State
    private var storagePrefix: String { profileSettings.selectedID.map { "HappyLuluAIUsage.providers.v2.\($0)" } ?? "HappyLuluAIUsage.codex-release" }
    private var historyKey: String { storagePrefix + ".history.v1" }
    private var notificationKey: String { storagePrefix + ".notification.v1" }
    private var notificationAccountKey: String { storagePrefix + ".notificationAccount.v1" }

    public init(defaults: UserDefaults = .standard, localize: @escaping PluginLocalizer = { ko, _ in ko },
                providerFactory: @escaping @Sendable (Preferences) -> any UsageProvider = {
                    CodexUsageProvider(executablePath: $0.cliPath, configDirectory: $0.configDirectory)
                }, providerRegistry: UsageProviderRegistry = .standard,
                notificationAuthorization: @escaping @MainActor @Sendable () async -> Bool = {
                    // Keep the non-Sendable settings object inside the system callback.
                    return await withCheckedContinuation { continuation in
                        UNUserNotificationCenter.current().getNotificationSettings { @Sendable settings in
                            let status = settings.authorizationStatus
                            continuation.resume(returning: status == .authorized || status == .provisional)
                        }
                    }
                }, notificationDelivery: @escaping @MainActor @Sendable (String, String, String) async throws -> Void = { id, title, body in
                    let content = UNMutableNotificationContent(); content.title = title; content.body = body
                    try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
                }, iconProvider: (@MainActor () -> Data?)? = nil) {
        self.defaults = defaults; self.localize = localize; self.providerFactory = providerFactory
        self.providerRegistry = providerRegistry
        let profiles = UsageProfileSettings.load(from: defaults, registry: providerRegistry)
        profileSettings = profiles
        self.notificationAuthorization = notificationAuthorization; self.notificationDelivery = notificationDelivery
        self.iconProvider = iconProvider ?? { CodexMenuBarIcon.loadPNG() }
        releasedPreferences = ReleasedUsagePreferences.load(from: defaults)
        preferences = profiles.selected?.preferences ?? releasedPreferences.preferences
        if defaults.object(forKey: ReleasedUsagePreferences.key) == nil, !profileSettings.readOnly, profileSettings.selectedID == nil {
            try? ReleasedUsagePreferences.save(releasedPreferences, to: defaults)
        }
        restoreStorage()
        if releasedPreferences.requiresConnection {
            message = localize("기존 연결 설정은 보존했습니다. Codex 실행 파일을 선택해 연결을 설정하세요.",
                               "Your previous connection is preserved. Choose the Codex executable to set up this connection.")
        }
        if settingsReadOnly {
            message = localize("사용량 설정을 읽지 못했습니다. 원본을 보존하며 조회와 변경을 중지합니다.",
                               "Usage settings could not be read. The original is preserved; requests and changes are paused.")
        }
    }

    public func text(_ korean: String, _ english: String) -> String { localize(korean, english) }
    public var selectedProfile: UsageProfile? { profileSettings.selected }
    public var providerName: String { selectedProfile.flatMap { providerRegistry.descriptor(for: $0.providerID)?.name } ?? providerFactory(preferences).name }
    public var usesCodexConnection: Bool { selectedProfile.flatMap { providerRegistry.descriptor(for: $0.providerID)?.connection } != .statusLine }
    public var supportsNotifications: Bool { usesCodexConnection || snapshot?.accountKey != nil }
    public var canRequestUsage: Bool {
        guard !settingsReadOnly else { return false }
        guard let profile = selectedProfile else { return !releasedPreferences.requiresConnection }
        guard let descriptor = providerRegistry.descriptor(for: profile.providerID) else { return false }
        return descriptor.connection == .codex ? profile.preferences.configDirectory.hasPrefix("/") : profile.reportPath.hasPrefix("/")
    }
    public var settingsReadOnly: Bool { releasedPreferences.readOnly || profileSettings.readOnly }
    private func currentProvider() -> any UsageProvider {
        if let profile = selectedProfile, let descriptor = providerRegistry.descriptor(for: profile.providerID) {
            return descriptor.makeProvider(profile)
        }
        return providerFactory(preferences)
    }
    public var connectionState: PluginConnectionState {
        if !enabled { return .off }
        if isRunning { return .connecting }
        if failed { return .attention }
        return snapshot == nil ? .setup : .ready
    }
    public var isStale: Bool {
        failed || snapshot?.isStale(intervalMinutes: preferences.refreshMinutes) == true ||
            (!usesCodexConnection && snapshot.map { Date().timeIntervalSince($0.fetchedAt) > 900 } == true)
    }
    public var analysis: UsageAnalysis { snapshot == nil ? UsageHistory().analysis() : history.analysis() }
    public var menuBarItem: PluginMenuBarItem? {
        guard active, enabled else { return nil }
        return menuBarPreview
    }
    public var menuBarPreview: PluginMenuBarItem {
        let name = providerName
        let value = snapshot.map { "\($0.weekly.remainingPercent)%" } ?? "—"
        let icon = preferences.labelFormat == .icon && usesCodexConnection ? cachedIconPNG : nil
        let title = preferences.labelFormat.title(remaining: snapshot?.weekly.remainingPercent,
            stale: isStale, providerName: name, iconAvailable: icon != nil)
        return PluginMenuBarItem(id: descriptor.id, title: title,
            accessibilityLabel: name + " " + text("주간 잔여량", "weekly remaining") + " " + value +
                (isStale ? text(" · 이전 조회 값", " · previous reading") : ""),
            iconPNG: icon, iconIsTemplate: icon != nil)
    }
    public func setEnabled(_ value: Bool) {
        enabled = value
        if !value { stop() }
    }
    public func start() {
        guard enabled, !active else { return }
        active = true
        guard canRequestUsage else {
            message = text("기존 설정은 보존했습니다. 선택한 공급자의 연결 설정을 확인해 주세요.",
                           "Your previous settings are preserved. Check the selected provider's connection settings.")
            return
        }
        schedule()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refreshData() } }
        refreshData()
    }
    public func stop() {
        active = false; generation += 1
        timer?.invalidate(); timer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        wakeObserver = nil
        task?.cancel(); task = nil
        loginAttempt?.cancel(); loginAttempt = nil
        loginTask?.cancel(); loginTask = nil
        isRefreshing = false; isLoggingIn = false; snapshot = nil; failed = false; message = nil
    }
    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Double(preferences.refreshMinutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshData() }
        }
    }
    public func refreshData() {
        guard enabled, active, !isRunning, canRequestUsage else { return }
        isRefreshing = true
        generation += 1
        let current = generation
        let provider = currentProvider()
        task = Task { [weak self] in
            do {
                let value = try await provider.fetch()
                guard let self, !Task.isCancelled, self.generation == current, self.active, self.enabled else { return }
                if self.notificationsWritable, self.defaults.string(forKey: self.notificationAccountKey) != value.accountKey {
                    self.alertGate = LowUsageAlertGate()
                    self.defaults.removeObject(forKey: self.notificationKey)
                    self.defaults.set(value.accountKey, forKey: self.notificationAccountKey)
                }
                self.snapshot = value
                if value.accountKey == nil { self.history.clear() }
                else { self.history.record(value, cadenceMinutes: self.preferences.refreshMinutes) }
                if self.historyWritable {
                    if self.history.canPersist, let data = try? JSONEncoder().encode(self.history) {
                        self.defaults.set(data, forKey: self.historyKey)
                    } else { self.defaults.removeObject(forKey: self.historyKey) }
                }
                self.failed = false; self.message = nil
                if value.accountKey != nil { await self.notifyIfNeeded(value.weekly, generation: current) }
            } catch {
                guard let self, !Task.isCancelled, self.generation == current, self.active else { return }
                self.failed = true
                self.message = self.errorMessage(error)
                if let error = error as? UsageError {
                    switch error {
                    case .notLoggedIn, .unsupportedAccount, .noWeeklyQuota, .noCodexQuota:
                        self.snapshot = nil; self.clearHistory()
                    default: break
                    }
                }
                if error is StatusLineUsageError { self.snapshot = nil; self.clearHistory() }
            }
            guard let self, self.generation == current else { return }
            self.isRefreshing = false; self.task = nil
        }
    }
    private func clearHistory() {
        history.clear()
        if historyWritable { defaults.removeObject(forKey: historyKey) }
    }
    private func restoreStorage() {
        history = UsageHistory(); historyWritable = true
        if defaults.object(forKey: historyKey) != nil {
            if let data = defaults.data(forKey: historyKey),
               let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               Set(object.keys).isSubset(of: ["accountKey", "resetsAt", "samples"]),
               let restored = try? JSONDecoder().decode(UsageHistory.self, from: data), restored.canPersist {
                history = restored
            } else { historyWritable = false }
        }
        notificationsWritable = [notificationKey, notificationAccountKey].allSatisfy {
            defaults.object(forKey: $0) == nil || defaults.object(forKey: $0) is String
        }
        if let key = defaults.string(forKey: notificationKey), key.range(of: #"^\d+-(10|20|30)$"#, options: .regularExpression) == nil {
            notificationsWritable = false
        }
        if let key = defaults.string(forKey: notificationAccountKey), key.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) == nil {
            notificationsWritable = false
        }
        alertGate = LowUsageAlertGate(deliveredKey: notificationsWritable ? defaults.string(forKey: notificationKey) : nil)
    }
    public func updatePreferences(_ change: (inout Preferences) -> Void) {
        guard !settingsReadOnly else { return }
        var next = preferences; change(&next); next.normalize()
        guard next != preferences else { return }
        var saved = releasedPreferences; saved.preferences = next
        do {
            if selectedProfile != nil {
                var profiles = profileSettings
                if let index = profiles.profiles.firstIndex(where: { $0.id == profiles.selectedID }) {
                    profiles.profiles[index].preferences = next
                }
                try profiles.save(to: defaults); profileSettings = profiles
            } else { try ReleasedUsagePreferences.save(saved, to: defaults) }
        }
        catch { message = errorMessage(error); return }
        let pathChanged = next.cliPath != preferences.cliPath || next.configDirectory != preferences.configDirectory
        preferences = next
        if selectedProfile == nil { releasedPreferences = saved }
        if pathChanged {
            let wasActive = active
            stop(); clearHistory()
            if wasActive { start() }
        } else if active && canRequestUsage { schedule() }
    }

    @discardableResult
    public func addProfile(providerID: String) -> String? {
        guard !settingsReadOnly, profileSettings.profiles.count < 32,
              let descriptor = providerRegistry.descriptor(for: providerID) else { return nil }
        let profile = UsageProfile(providerID: providerID, name: descriptor.name)
        var next = profileSettings; next.profiles.append(profile); next.selectedID = profile.id
        return applyProfiles(next) ? profile.id : nil
    }

    public func selectProfile(_ id: String?) {
        guard !settingsReadOnly, id != profileSettings.selectedID,
              id == nil || profileSettings.profiles.contains(where: { $0.id == id }) else { return }
        var next = profileSettings; next.selectedID = id
        _ = applyProfiles(next)
    }

    public func updateSelectedProfile(_ change: (inout UsageProfile) -> Void) {
        guard !settingsReadOnly, let index = profileSettings.profiles.firstIndex(where: { $0.id == profileSettings.selectedID }) else { return }
        var next = profileSettings; change(&next.profiles[index])
        guard next.profiles[index] != profileSettings.profiles[index] else { return }
        if next.profiles[index].preferences == profileSettings.profiles[index].preferences,
           next.profiles[index].reportPath == profileSettings.profiles[index].reportPath {
            do { try next.save(to: defaults); profileSettings = next }
            catch { message = errorMessage(error) }
            return
        }
        _ = applyProfiles(next)
    }

    public func removeSelectedProfile() {
        guard !settingsReadOnly, let id = profileSettings.selectedID else { return }
        var next = profileSettings; next.profiles.removeAll { $0.id == id }; next.selectedID = nil
        _ = applyProfiles(next)
    }

    private func applyProfiles(_ next: UsageProfileSettings) -> Bool {
        do { try next.save(to: defaults) }
        catch { message = errorMessage(error); return false }
        let wasActive = active
        stop()
        profileSettings = next
        preferences = next.selected?.preferences ?? releasedPreferences.preferences
        restoreStorage()
        if wasActive { start() }
        return true
    }

    public func chooseProfileFile() {
        guard !settingsReadOnly, selectedProfile != nil else { return }
        let panel = NSOpenPanel()
        panel.title = usesCodexConnection ? text("Codex 전용 계정 폴더 선택", "Choose a dedicated Codex account folder") : text("사용량 내보내기 파일 선택", "Choose a usage export file")
        panel.canChooseDirectories = usesCodexConnection; panel.canChooseFiles = !usesCodexConnection
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if usesCodexConnection { updateSelectedProfile { $0.preferences.configDirectory = url.path } }
        else { updateSelectedProfile { $0.reportPath = url.path } }
    }

    public func saveStatusLineHelper() {
        guard !settingsReadOnly, !usesCodexConnection else { return }
        guard let source = StatusLineUsageProvider.exporterURL else {
            message = text("앱에 내보내기 도우미가 없습니다. 앱 패키지를 확인하세요.", "The app's export helper is missing. Check the app package.")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "export-ai-usage.py"
        panel.title = text("사용량 내보내기 도우미 저장", "Save usage export helper")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(contentsOf: source).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            message = text("도우미를 저장했습니다. 연결 안내에 따라 기존 statusLine에 직접 연결한 후 사용량 파일을 선택하세요.",
                           "Helper saved. Connect it to your existing statusLine explicitly, then choose the usage file.")
        } catch { message = text("도우미를 저장하지 못했습니다.", "Could not save the helper.") }
    }

    public func chooseExecutable() {
        guard !settingsReadOnly, usesCodexConnection else { return }
        let panel = NSOpenPanel()
        panel.title = text("Codex 실행 파일 선택", "Choose Codex executable")
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try CodexExecutable.resolve(customPath: url.path)
            try acceptExecutable(url.path)
        } catch { message = errorMessage(error) }
    }
    func acceptExecutable(_ path: String) throws {
        guard !settingsReadOnly, usesCodexConnection else { throw CocoaError(.fileWriteNoPermission) }
        _ = try CodexExecutable.resolve(customPath: path)
        if selectedProfile != nil { updatePreferences { $0.cliPath = path }; return }
        var saved = releasedPreferences
        saved.preferences.cliPath = path
        saved.requiresConnection = false
        try ReleasedUsagePreferences.save(saved, to: defaults)
        let wasActive = active
        stop(); clearHistory()
        releasedPreferences = saved; preferences = saved.preferences
        if wasActive { start() }
    }
    public var executablePath: String { usesCodexConnection ? ((try? CodexExecutable.resolve(customPath: preferences.cliPath).path) ?? "—") : (selectedProfile?.reportPath ?? "—") }
    public func login() {
        guard active, enabled, !isRunning, canRequestUsage,
              let attempt = currentProvider().makeLoginAttempt() else { return }
        generation += 1
        let current = generation
        loginAttempt = attempt; isLoggingIn = true
        message = text("브라우저에서 인증을 완료해 주세요.", "Complete sign-in in your browser.")
        loginTask = Task { [weak self] in
            do {
                try await attempt.login { [weak self] url in
                    Task { @MainActor in
                        guard let self, self.active, self.generation == current else { return }
                        if !NSWorkspace.shared.open(url) { self.cancelLogin() }
                    }
                }
                guard let self, !Task.isCancelled, self.active, self.generation == current else { return }
                self.loginAttempt = nil; self.loginTask = nil; self.isLoggingIn = false
                self.snapshot = nil; self.clearHistory(); self.message = nil
                self.alertGate = LowUsageAlertGate()
                if self.notificationsWritable { self.defaults.removeObject(forKey: self.notificationKey) }
                self.refreshData()
            } catch {
                guard let self, !Task.isCancelled, self.generation == current else { return }
                self.loginAttempt = nil; self.loginTask = nil; self.isLoggingIn = false
                self.message = self.errorMessage(error)
            }
        }
    }
    public func cancelLogin() {
        generation += 1
        loginAttempt?.cancel(); loginAttempt = nil
        loginTask?.cancel(); loginTask = nil
        isLoggingIn = false; message = nil
    }
    private func notifyIfNeeded(_ window: UsageWindow, generation current: Int) async {
        guard notificationsWritable else { return }
        let threshold = preferences.notificationThreshold
        guard let key = alertGate.pendingKey(for: window, threshold: threshold,
            enabled: preferences.notificationsEnabled) else { return }
        let authorized = await notificationAuthorization()
        guard active, enabled, generation == current, preferences.notificationsEnabled, authorized,
              preferences.notificationThreshold == threshold else { return }
        let title = text("\(providerName) 주간 잔여량 \(window.remainingPercent)%", "\(providerName) weekly remaining \(window.remainingPercent)%")
        let body = text("설정한 \(threshold)% 이하입니다.", "At or below your \(threshold)% threshold.")
        do {
            try await notificationDelivery(storagePrefix + "-" + key, title, body)
            guard active, generation == current else { return }
            alertGate.markDelivered(key); defaults.set(key, forKey: notificationKey)
        } catch {
            guard active, generation == current else { return }
            message = text("알림을 보내지 못했습니다. 시스템 알림 설정을 확인해 주세요.", "Could not send a notification. Check System Settings.")
        }
    }
    public func setNotifications(_ enabled: Bool) {
        guard !settingsReadOnly, !enabled || supportsNotifications else { return }
        updatePreferences { $0.notificationsEnabled = enabled }
        guard enabled else { return }
        let current = generation
        Task { [weak self] in
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) == true
            guard let self, self.enabled, self.generation == current, self.preferences.notificationsEnabled else { return }
            if !granted {
                self.updatePreferences { $0.notificationsEnabled = false }
                self.message = self.text("시스템 설정에서 HappyLulu 알림을 허용해 주세요.", "Allow HappyLulu notifications in System Settings.")
            }
        }
    }
    private func errorMessage(_ error: Error) -> String {
        if localize("ko", "en") == "ko" { return error.localizedDescription }
        if let error = error as? StatusLineUsageError {
            switch error {
            case .unavailable: return "Choose a private regular usage file owned by your user."
            case .invalidReport: return "The usage file has an invalid format or belongs to another provider."
            case .staleReport: return "The reading is old or the quota expired. Export a fresh reading from the CLI."
            case .noWeeklyQuota: return "This connection did not provide a weekly quota."
            }
        }
        switch error as? UsageError {
        case .notLoggedIn: return "Sign in with ChatGPT to view weekly usage."
        case .unsupportedAccount: return "API key accounts do not provide a ChatGPT weekly allowance."
        case .cliNotFound: return "Codex was not found. Choose the executable in connection settings."
        case .noWeeklyQuota: return "This account did not provide a weekly allowance."
        case .timeout, .loginTimeout: return "The request timed out. Try again."
        default: return "Could not read Codex usage. Check your connection and sign-in, then refresh."
        }
    }
}
