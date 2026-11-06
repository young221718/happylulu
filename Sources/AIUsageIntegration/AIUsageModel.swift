import AppKit
import Combine
import UserNotifications
import UniformTypeIdentifiers
import AIUsagePlugin
import AppPluginCore
import AppPluginHost

public enum TokenMeasurementSource: String, Sendable {
    case codexRecentSessions, newSession, codexSessionFile
}

private actor CodexSessionPoller {
    private var reader: CodexSessionTokenSpeedReader
    init(path: String) throws { reader = try CodexSessionTokenSpeedReader(path: path) }
    struct Result: Sendable {
        let samples: [TokenSpeedSample]
        let scopeKey: String
        let hasMoreData: Bool
        let invalidatedRequestKeys: Set<String>
    }
    func poll() throws -> Result {
        let samples = try reader.poll()
        return Result(samples: samples, scopeKey: reader.scopeKey, hasMoreData: reader.hasMoreData,
            invalidatedRequestKeys: reader.invalidatedRequestKeys)
    }
}

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
    @Published public private(set) var tokenTelemetryConnection: TokenTelemetryConnection?
    @Published public private(set) var isTokenMeasurementStarting = false
    @Published public private(set) var tokenTelemetryMessage: String?
    @Published public private(set) var tokenMeasurementSource: TokenMeasurementSource = .codexRecentSessions
    @Published public private(set) var codexSessionFilePath = ""
    @Published public private(set) var isObservingCodexSession = false
    @Published public private(set) var recentCodexSessionCount = 0
    @Published public private(set) var unsupportedCodexSessionCount = 0
    @Published public private(set) var isCatchingUpCodexSessions = false
    @Published private var tokenSpeedSample: TokenSpeedSample?
    @Published private var history: UsageHistory
    public var changes: AnyPublisher<Void, Never> { objectWillChange.map { _ in () }.eraseToAnyPublisher() }
    private let defaults: UserDefaults
    private let localize: PluginLocalizer
    private let notificationAuthorization: @MainActor @Sendable () async -> Bool
    private let notificationDelivery: @MainActor @Sendable (String, String, String) async throws -> Void
    private let providerFactory: @Sendable (Preferences) -> any UsageProvider
    private let recentSessionMonitorFactory: @Sendable (String) throws -> any CodexRecentSessionMonitoring
    private let telemetryReceiverFactory: @MainActor (UsageProviderKind, @escaping @Sendable ([TokenSpeedSample]) -> Void) -> any TokenTelemetryReceiving
    private let bridgeExecutablePath: String?
    private let iconProvider: @MainActor () -> Data?
    private lazy var cachedIconPNG: Data? = iconProvider().flatMap { NSImage(data: $0) == nil ? nil : $0 }
    private var active = false
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var task: Task<Void, Never>?
    private var loginTask: Task<Void, Never>?
    private var loginAttempt: (any UsageLoginAttempt)?
    private var telemetryReceiver: (any TokenTelemetryReceiving)?
    private var telemetryTask: Task<Void, Never>?
    private var telemetryGeneration = 0
    private var telemetryAccountKey: String?
    private var telemetryProvider: UsageProviderKind?
    private var generation = 0
    private var failed = false
    private var alertGate: LowUsageAlertGate
    private let preferencesKey = "HappyLuluAIUsage.preferences.v1"
    private var historyKey: String { storageKey("history") }
    private var notificationKey: String { storageKey("notification") }
    private var notificationAccountKey: String { storageKey("notificationAccount") }
    private func storageKey(_ kind: String) -> String {
        let base = "HappyLuluAIUsage.\(kind).v1"
        return preferences.selectedProfileID == UsageProfile.defaultCodexID ? base : base + "." + preferences.selectedProfileID
    }

    public init(defaults: UserDefaults = .standard,
                recentSessionMonitorFactory: @escaping @Sendable (String) throws -> any CodexRecentSessionMonitoring = { try CodexRecentSessionMonitor(codexHome: $0) },
                localize: @escaping PluginLocalizer = { ko, _ in ko },
                providerFactory: @escaping @Sendable (Preferences) -> any UsageProvider = {
                    switch $0.selectedProfile.provider {
                    case .codex: return CodexUsageProvider(executablePath: $0.cliPath, configDirectory: $0.selectedProfile.configDirectory)
                    case .claude: return UnavailableUsageProvider()
                    case .antigravity: return AntigravityUsageProvider(executablePath: $0.cliPath, configDirectory: $0.selectedProfile.configDirectory,
                        allowCLIExecution: $0.selectedProfile.allowAntigravityCLI)
                    }
                }, notificationAuthorization: @escaping @MainActor @Sendable () async -> Bool = {
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
                }, iconProvider: (@MainActor () -> Data?)? = nil,
                telemetryReceiverFactory: @escaping @MainActor (UsageProviderKind, @escaping @Sendable ([TokenSpeedSample]) -> Void) -> any TokenTelemetryReceiving = { TokenTelemetryReceiver(provider: $0, onSamples: $1) },
                bridgeExecutablePath: String? = Bundle.main.executableURL?.path) {
        self.defaults = defaults; self.localize = localize; self.providerFactory = providerFactory
        self.recentSessionMonitorFactory = recentSessionMonitorFactory
        self.notificationAuthorization = notificationAuthorization; self.notificationDelivery = notificationDelivery
        self.telemetryReceiverFactory = telemetryReceiverFactory
        self.bridgeExecutablePath = bridgeExecutablePath
        self.iconProvider = iconProvider ?? { CodexMenuBarIcon.loadPNG() }
        var saved = defaults.data(forKey: "HappyLuluAIUsage.preferences.v1")
            .flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        saved.normalize(); preferences = saved
        tokenMeasurementSource = saved.selectedProfile.provider == .codex ? .codexRecentSessions : .newSession
        let suffix = saved.selectedProfileID == UsageProfile.defaultCodexID ? "" : "." + saved.selectedProfileID
        history = defaults.data(forKey: "HappyLuluAIUsage.history.v1" + suffix)
            .flatMap { try? JSONDecoder().decode(UsageHistory.self, from: $0) } ?? UsageHistory()
        alertGate = LowUsageAlertGate(deliveredKey: defaults.string(forKey: "HappyLuluAIUsage.notification.v1" + suffix))
    }

    public var selectedProfile: UsageProfile { preferences.selectedProfile }
    public var providerName: String { providerFactory(preferences).name }
    public var supportsLogin: Bool { selectedProfile.provider == .codex }
    public var canStartTokenMeasurement: Bool {
        guard selectedProfile.provider.isSupported, active, enabled, !isTokenMeasurementStarting, tokenTelemetryConnection == nil, !isObservingCodexSession else { return false }
        if selectedProfile.provider == .codex, tokenMeasurementSource == .codexSessionFile {
            return !isObservingCodexSession && !codexSessionFilePath.isEmpty
        }
        return true
    }
    public var currentTokenSpeedSample: TokenSpeedSample? {
        guard let sample = tokenSpeedSample, tokenTelemetryConnection != nil || isObservingCodexSession,
              sample.accountKey == telemetryAccountKey, selectedProfile.provider == telemetryProvider else { return nil }
        let age = Date().timeIntervalSince(sample.recordedAt)
        return (0...900).contains(age) ? sample : nil
    }
    public var tokenSpeedDisplayTitle: String {
        switch selectedProfile.provider {
        case .claude: return text("출력 속도(지원 안 함)", "Output speed (unavailable)")
        case .antigravity: return text("완료 단계 평균 출력 속도", "Completed-step average output speed")
        case .codex:
            guard tokenMeasurementSource != .newSession else {
                return text("응답 스트림 평균 출력 속도", "Response-stream average output speed")
            }
            switch currentTokenSpeedSample.flatMap(CodexSessionTokenSpeedReader.metricKind(for:)) {
            case .message: return text("메시지 평균 출력 속도(로컬 세션)", "Message-average output speed (local session)")
            case .completedTurn: return text("완료 턴 평균 출력 속도(로컬 세션)", "Completed-turn average output speed (local session)")
            case .inProgressTurn: return text("진행 턴 평균 출력 속도(마지막 기록까지)", "In-progress turn average output speed (last recorded)")
            case nil: return text("평균 출력 속도(로컬 세션)", "Average output speed (local session)")
            }
        }
    }
    public var tokenTelemetryCommand: String? {
        guard let connection = tokenTelemetryConnection else { return nil }
        if selectedProfile.provider == .codex { return codexTokenCommand(connection) }
        if selectedProfile.provider == .antigravity { return antigravityTokenCommand(connection) }
        return nil
    }
    private func codexTokenCommand(_ connection: TokenTelemetryConnection) -> String? {
        let removed = ["OTEL_EXPORTER_OTLP_HEADERS", "OTEL_EXPORTER_OTLP_TRACES_HEADERS", "OTEL_EXPORTER_OTLP_COMPRESSION", "OTEL_EXPORTER_OTLP_TRACES_COMPRESSION"]
        var arguments = removed.flatMap { ["-u", $0] }
        arguments += ["NO_PROXY=127.0.0.1,localhost", "no_proxy=127.0.0.1,localhost"]
        if !selectedProfile.configDirectory.isEmpty { arguments.append("CODEX_HOME=" + selectedProfile.configDirectory) }
        let exporter = "otel.trace_exporter={otlp-http={endpoint=" + Self.tomlString(connection.endpoint.absoluteString) +
            ",protocol=\"json\",headers={Authorization=" + Self.tomlString(connection.authorizationHeader) + "}}}"
        arguments += [preferences.cliPath.isEmpty ? "codex" : preferences.cliPath,
            "-c", "otel.exporter=\"none\"", "-c", "otel.metrics_exporter=\"none\"", "-c", "otel.log_user_prompt=false",
            "-c", "otel.log_agent_responses=false", "-c", "otel.log_guardian_assessments=false", "-c", exporter]
        return "env " + arguments.map(Self.shellQuote).joined(separator: " ")
    }
    private func antigravityTokenCommand(_ connection: TokenTelemetryConnection) -> String? {
        guard let bridgeExecutablePath, let scope = telemetryAccountKey else { return nil }
        let executable = preferences.cliPath.isEmpty ? "agy" : preferences.cliPath
        let bridge = ["env", "HAPPY_LULU_TOKEN_ENDPOINT=" + connection.endpoint.absoluteString,
            "HAPPY_LULU_TOKEN_AUTH=" + connection.authorizationHeader, "HAPPY_LULU_TOKEN_SCOPE=" + scope,
            bridgeExecutablePath, "--token-speed-bridge", "antigravity"].map(Self.shellQuote).joined(separator: " ")
        let script = "set -o pipefail; printf '%s' 'Antigravity prompt: '; IFS= read -r HAPPY_LULU_PROMPT || exit 1; " +
            Self.shellQuote(executable) + " -p \"$HAPPY_LULU_PROMPT\" --output-format stream-json | " + bridge
        return "/bin/bash -c " + Self.shellQuote(script)
    }
    private static func tomlString(_ value: String) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(data: try! encoder.encode(value), encoding: .utf8)!
    }
    private static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    public func text(_ korean: String, _ english: String) -> String { localize(korean, english) }
    public var connectionState: PluginConnectionState {
        if !enabled { return .off }
        if isRunning { return .connecting }
        if failed { return .attention }
        return snapshot == nil ? .setup : .ready
    }
    public var isStale: Bool { failed || snapshot?.isStale(intervalMinutes: preferences.refreshMinutes) == true }
    public var analysis: UsageAnalysis { snapshot == nil ? UsageHistory().analysis() : history.analysis() }
    public var menuBarItem: PluginMenuBarItem? {
        guard active, enabled else { return nil }
        return menuBarPreview
    }
    public var menuBarPreview: PluginMenuBarItem {
        let name = providerName
        let value = snapshot.map { "\($0.weekly.remainingPercent)%" } ?? "—"
        let icon = preferences.labelFormat == .icon && selectedProfile.provider == .codex ? cachedIconPNG : nil
        let speed = currentTokenSpeedSample.map { String(format: "%.1f tok/s", $0.tokensPerSecond) }
        let title = preferences.labelFormat.title(remaining: snapshot?.weekly.remainingPercent,
            stale: isStale, providerName: name, iconAvailable: icon != nil)
        return PluginMenuBarItem(id: descriptor.id, title: title + (speed.map { " · " + $0 } ?? ""),
            accessibilityLabel: name + " " + text("주간 잔여량", "weekly remaining") + " " + value +
                (isStale ? text(" · 이전 조회 값", " · previous reading") : "") +
                (speed.map { " · " + tokenSpeedDisplayTitle + " " + $0 } ?? ""),
            iconPNG: icon, iconIsTemplate: icon != nil)
    }
    public func setEnabled(_ value: Bool) {
        enabled = value
        if !value { stop() }
    }
    public func start() {
        guard enabled, !active else { return }
        active = true
        schedule()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refreshData() } }
        refreshData()
        if selectedProfile.provider == .codex, tokenMeasurementSource == .codexRecentSessions { startTokenMeasurement() }
    }
    public func stop() {
        active = false; generation += 1
        stopTokenMeasurement()
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
        guard enabled, active, !isRunning else { return }
        guard selectedProfile.provider.isSupported else {
            snapshot = nil; failed = true; message = errorMessage(UsageError.unsupportedProvider)
            return
        }
        isRefreshing = true
        generation += 1
        let current = generation
        let provider = providerFactory(preferences)
        task = Task { [weak self] in
            do {
                let value = try await provider.fetch()
                guard let self, !Task.isCancelled, self.generation == current, self.active, self.enabled else { return }
                if self.defaults.string(forKey: self.notificationAccountKey) != value.accountKey {
                    self.alertGate = LowUsageAlertGate()
                    self.defaults.removeObject(forKey: self.notificationKey)
                    self.defaults.set(value.accountKey, forKey: self.notificationAccountKey)
                }
                self.snapshot = value
                if let account = value.accountKey, !account.isEmpty {
                    self.history.record(value, cadenceMinutes: self.preferences.refreshMinutes)
                } else { self.clearHistory() }
                if self.history.canPersist, let data = try? JSONEncoder().encode(self.history) {
                    self.defaults.set(data, forKey: self.historyKey)
                } else { self.defaults.removeObject(forKey: self.historyKey) }
                self.failed = false; self.message = nil
                if let account = value.accountKey, !account.isEmpty {
                    await self.notifyIfNeeded(value.weekly, generation: current)
                }
            } catch {
                guard let self, !Task.isCancelled, self.generation == current, self.active else { return }
                self.failed = true
                self.message = self.errorMessage(error)
                if self.invalidatesReading(error) {
                    self.snapshot = nil; self.clearHistory()
                }
            }
            guard let self, self.generation == current else { return }
            self.isRefreshing = false; self.task = nil
        }
    }
    private func clearHistory() {
        history.clear(); defaults.removeObject(forKey: historyKey)
    }
    public func updatePreferences(_ change: (inout Preferences) -> Void) {
        var next = preferences; change(&next); next.normalize()
        guard next != preferences, let data = try? JSONEncoder().encode(next) else { return }
        let oldProfile = preferences.selectedProfile
        let nextProfile = next.selectedProfile
        let switched = oldProfile.id != nextProfile.id
        let connectionChanged = oldProfile.provider != nextProfile.provider || oldProfile.cliPath != nextProfile.cliPath ||
            oldProfile.allowAntigravityCLI != nextProfile.allowAntigravityCLI ||
            oldProfile.configDirectory != nextProfile.configDirectory
        let wasActive = active
        if switched || connectionChanged { stop() }
        if switched || connectionChanged {
            tokenMeasurementSource = nextProfile.provider == .codex ? .codexRecentSessions : .newSession; codexSessionFilePath = ""
        }
        preferences = next; defaults.set(data, forKey: preferencesKey)
        if switched {
            restoreProfileState()
        } else if connectionChanged {
            clearHistory()
            alertGate = LowUsageAlertGate()
            defaults.removeObject(forKey: notificationKey)
            defaults.removeObject(forKey: notificationAccountKey)
        }
        if switched || connectionChanged {
            if wasActive { start() }
        } else if active { schedule() }
    }
    private func restoreProfileState() {
        history = defaults.data(forKey: historyKey).flatMap { try? JSONDecoder().decode(UsageHistory.self, from: $0) } ?? UsageHistory()
        alertGate = LowUsageAlertGate(deliveredKey: defaults.string(forKey: notificationKey))
    }
    @discardableResult public func addProfile(provider: UsageProviderKind, name: String? = nil) -> String {
        guard provider.isSupported else { return preferences.selectedProfileID }
        if provider == .antigravity, let existing = preferences.profiles.first(where: { $0.provider == .antigravity }) {
            selectProfile(existing.id)
            return existing.id
        }
        let profile = UsageProfile(name: name ?? provider.name, provider: provider)
        updatePreferences { $0.profiles.append(profile); $0.selectedProfileID = profile.id }
        return profile.id
    }
    public func selectProfile(_ id: String) {
        guard preferences.profiles.contains(where: { $0.id == id }) else { return }
        updatePreferences { $0.selectedProfileID = id }
    }
    public func removeSelectedProfile() {
        guard preferences.profiles.count > 1 else { return }
        let removed = preferences.selectedProfileID
        updatePreferences {
            $0.profiles.removeAll { $0.id == removed }
            $0.selectedProfileID = $0.profiles[0].id
        }
    }
    public func updateSelectedProfile(_ change: (inout UsageProfile) -> Void) {
        updatePreferences { $0.updateSelectedProfile(change) }
    }
    public func setConfigDirectory(_ value: String) {
        let path = (value.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard path.isEmpty || path.hasPrefix("/") else {
            message = text("절대 경로를 입력해 주세요.", "Enter an absolute path.")
            return
        }
        updateSelectedProfile { $0.configDirectory = path }
    }
    public func startTokenMeasurement() {
        guard canStartTokenMeasurement else { return }
        if selectedProfile.provider == .codex, tokenMeasurementSource == .codexRecentSessions {
            startRecentCodexSessionObservation(); return
        }
        if selectedProfile.provider == .codex, tokenMeasurementSource == .codexSessionFile {
            startCodexSessionObservation(); return
        }
        let provider = selectedProfile.provider
        let accountKey: String
        switch provider {
        case .claude: return
        case .codex: accountKey = "codex-profile:" + selectedProfile.id
        case .antigravity: accountKey = "antigravity:" + UUID().uuidString
        }
        telemetryGeneration += 1
        let current = telemetryGeneration
        let profileID = selectedProfile.id
        telemetryAccountKey = accountKey
        telemetryProvider = provider
        tokenTelemetryMessage = nil; tokenSpeedSample = nil; isTokenMeasurementStarting = true
        let receiver = telemetryReceiverFactory(provider) { [weak self] samples in
            Task { @MainActor in
                guard let self, self.telemetryGeneration == current, self.active, self.enabled,
                      self.selectedProfile.id == profileID, self.selectedProfile.provider == provider else { return }
                let now = Date()
                if let latest = samples.filter({ $0.accountKey == accountKey && (0...900).contains(now.timeIntervalSince($0.recordedAt)) })
                    .max(by: { $0.recordedAt < $1.recordedAt }),
                   self.tokenSpeedSample.map({ latest.recordedAt > $0.recordedAt }) ?? true {
                    self.tokenSpeedSample = latest
                }
            }
        }
        telemetryReceiver = receiver
        telemetryTask = Task { [weak self] in
            do {
                let connection = try await receiver.start(accountKey: accountKey)
                guard let self, !Task.isCancelled, self.telemetryGeneration == current, self.active, self.enabled,
                      self.selectedProfile.id == profileID, self.selectedProfile.provider == provider else {
                    receiver.stop(); return
                }
                self.tokenTelemetryConnection = connection
                self.isTokenMeasurementStarting = false; self.telemetryTask = nil
            } catch {
                guard let self, self.telemetryGeneration == current else { return }
                receiver.stop(); self.telemetryReceiver = nil; self.telemetryTask = nil
                self.telemetryAccountKey = nil; self.telemetryProvider = nil
                self.isTokenMeasurementStarting = false
                self.tokenTelemetryMessage = self.text("로컬 토큰 측정을 시작하지 못했습니다. 다시 시도해 주세요.", "Could not start local token measurement. Try again.")
            }
        }
    }
    public func stopTokenMeasurement() {
        telemetryGeneration += 1
        telemetryTask?.cancel(); telemetryTask = nil
        telemetryReceiver?.stop(); telemetryReceiver = nil
        telemetryAccountKey = nil; telemetryProvider = nil
        tokenTelemetryConnection = nil; tokenSpeedSample = nil
        tokenTelemetryMessage = nil; isTokenMeasurementStarting = false
        isObservingCodexSession = false
        recentCodexSessionCount = 0; unsupportedCodexSessionCount = 0; isCatchingUpCodexSessions = false
    }
    public func setTokenMeasurementSource(_ source: TokenMeasurementSource) {
        guard selectedProfile.provider == .codex, source != tokenMeasurementSource else { return }
        stopTokenMeasurement(); tokenMeasurementSource = source
        if source == .codexRecentSessions { startTokenMeasurement() }
    }
    public func setCodexSessionFile(_ value: String) {
        guard selectedProfile.provider == .codex else { return }
        let path = (value.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard path.isEmpty || path.hasPrefix("/") else {
            tokenTelemetryMessage = text("세션 파일의 절대 경로를 선택해 주세요.", "Choose an absolute session-file path."); return
        }
        stopTokenMeasurement(); codexSessionFilePath = path
    }
    public func chooseCodexSessionFile() {
        let panel = NSOpenPanel()
        panel.title = text("관측할 Codex 세션 JSONL 선택", "Choose a Codex session JSONL to observe")
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "jsonl") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setCodexSessionFile(url.path)
    }
    private func startRecentCodexSessionObservation() {
        stopTokenMeasurement()
        let current = telemetryGeneration, profileID = selectedProfile.id
        let configured = selectedProfile.configDirectory.isEmpty ? ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "" : selectedProfile.configDirectory
        let home = configured.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path :
            (configured as NSString).expandingTildeInPath
        telemetryProvider = .codex; isTokenMeasurementStarting = true
        let factory = recentSessionMonitorFactory
        telemetryTask = Task { [weak self] in
            do {
                let monitor = try factory(home)
                while !Task.isCancelled {
                    let value = try await monitor.poll(now: Date())
                    guard let self, !Task.isCancelled, self.telemetryGeneration == current, self.active, self.enabled,
                          self.selectedProfile.id == profileID, self.selectedProfile.provider == .codex,
                          self.tokenMeasurementSource == .codexRecentSessions else { return }
                    self.telemetryAccountKey = monitor.scopeKey
                    self.isObservingCodexSession = true; self.isTokenMeasurementStarting = false
                    self.recentCodexSessionCount = value.discoveredSessionCount
                    self.unsupportedCodexSessionCount = value.unsupportedSessionCount
                    self.isCatchingUpCodexSessions = value.isCatchingUp
                    let now = Date()
                    self.tokenSpeedSample = value.latestSample.flatMap {
                        $0.accountKey == monitor.scopeKey && (0...900).contains(now.timeIntervalSince($0.recordedAt)) ? $0 : nil
                    }
                    if value.isCatchingUp { await Task.yield() }
                    else { try await Task.sleep(for: .seconds(1)) }
                }
            } catch {
                guard let self, !Task.isCancelled, self.telemetryGeneration == current else { return }
                self.stopTokenMeasurement()
                self.tokenTelemetryMessage = self.text("최근 Codex 세션을 읽지 못했습니다. 계정 폴더 경로를 확인하거나 세션 파일을 선택해 주세요.", "Could not read recent Codex sessions. Check the account folder or select a session file.")
            }
        }
    }
    private func startCodexSessionObservation() {
        stopTokenMeasurement()
        telemetryGeneration += 1
        let current = telemetryGeneration, profileID = selectedProfile.id, path = codexSessionFilePath
        telemetryProvider = .codex; isTokenMeasurementStarting = true
        telemetryTask = Task { [weak self] in
            do {
                let poller = try CodexSessionPoller(path: path)
                while !Task.isCancelled {
                    let value = try await poller.poll()
                    guard let self, !Task.isCancelled, self.telemetryGeneration == current, self.active, self.enabled,
                          self.selectedProfile.id == profileID, self.selectedProfile.provider == .codex,
                          self.tokenMeasurementSource == .codexSessionFile else { return }
                    if self.telemetryAccountKey != value.scopeKey { self.tokenSpeedSample = nil }
                    if let sample = self.tokenSpeedSample, value.invalidatedRequestKeys.contains(sample.requestKey) {
                        self.tokenSpeedSample = nil
                    }
                    self.telemetryAccountKey = value.scopeKey
                    self.isObservingCodexSession = true; self.isTokenMeasurementStarting = false
                    let now = Date()
                    if let latest = value.samples.filter({ $0.accountKey == value.scopeKey && (0...900).contains(now.timeIntervalSince($0.recordedAt)) })
                        .max(by: { $0.recordedAt < $1.recordedAt }),
                       self.tokenSpeedSample.map({ latest.recordedAt > $0.recordedAt ||
                           (latest.recordedAt == $0.recordedAt && latest.requestKey == $0.requestKey) }) ?? true { self.tokenSpeedSample = latest }
                    if value.hasMoreData { await Task.yield() }
                    else { try await Task.sleep(for: .seconds(1)) }
                }
            } catch {
                guard let self, !Task.isCancelled, self.telemetryGeneration == current else { return }
                self.telemetryTask = nil; self.telemetryAccountKey = nil; self.telemetryProvider = nil
                self.tokenSpeedSample = nil; self.isObservingCodexSession = false; self.isTokenMeasurementStarting = false
                self.tokenTelemetryMessage = self.text("이 Codex 세션을 안전하게 읽지 못했습니다. 출력 토큰 수와 시간이 기록된 JSONL 파일을 선택해 주세요.", "Could not safely read this Codex session. Choose a supported JSONL file with output token and timing fields.")
            }
        }
    }
    public func chooseUsageReport() {
        let panel = NSOpenPanel()
        panel.title = text("Antigravity 사용량 JSON 선택", "Choose Antigravity usage JSON")
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setConfigDirectory(url.path)
    }
    public func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = text("\(providerName) 실행 파일 선택", "Choose \(providerName) executable")
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.isExecutableFile(atPath: url.path), !url.hasDirectoryPath else {
            message = text("실행 가능한 파일을 선택해 주세요.", "Choose an executable file.")
            return
        }
        updatePreferences { $0.cliPath = url.path }
    }
    public var executablePath: String {
        if selectedProfile.provider == .codex { return (try? CodexExecutable.resolve(customPath: preferences.cliPath).path) ?? "—" }
        return preferences.cliPath.isEmpty ? text("자동 찾기", "Find automatically") : preferences.cliPath
    }
    public func login() {
        guard selectedProfile.provider.isSupported, active, enabled, !isRunning,
              let attempt = providerFactory(preferences).makeLoginAttempt() else { return }
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
                self.alertGate = LowUsageAlertGate(); self.defaults.removeObject(forKey: self.notificationKey)
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
        let threshold = preferences.notificationThreshold
        guard let key = alertGate.pendingKey(for: window, threshold: threshold,
            enabled: preferences.notificationsEnabled) else { return }
        let authorized = await notificationAuthorization()
        guard active, enabled, generation == current, preferences.notificationsEnabled, authorized,
              preferences.notificationThreshold == threshold else { return }
        let title = text("\(providerName) 주간 잔여량 \(window.remainingPercent)%", "\(providerName) weekly remaining \(window.remainingPercent)%")
        let body = text("설정한 \(threshold)% 이하입니다.", "At or below your \(threshold)% threshold.")
        do {
            try await notificationDelivery("ai-usage-" + preferences.selectedProfileID + "-" + key, title, body)
            guard active, generation == current else { return }
            alertGate.markDelivered(key); defaults.set(key, forKey: notificationKey)
        } catch {
            guard active, generation == current else { return }
            message = text("알림을 보내지 못했습니다. 시스템 알림 설정을 확인해 주세요.", "Could not send a notification. Check System Settings.")
        }
    }
    public func setNotifications(_ enabled: Bool) {
        updatePreferences { $0.notificationsEnabled = enabled }
        guard enabled else { return }
        Task { [weak self] in
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) == true
            guard let self, self.enabled, self.preferences.notificationsEnabled else { return }
            if !granted {
                self.updatePreferences { $0.notificationsEnabled = false }
                self.message = self.text("시스템 설정에서 HappyLulu 알림을 허용해 주세요.", "Allow HappyLulu notifications in System Settings.")
            }
        }
    }
    private func invalidatesReading(_ error: Error) -> Bool {
        if error is AntigravityUsageError { return true }
        if let error = error as? UsageError {
            switch error {
            case .notLoggedIn, .unsupportedAccount, .noWeeklyQuota, .noCodexQuota, .unsupportedProvider: return true
            default: break
            }
        }
        return false
    }
    private func errorMessage(_ error: Error) -> String {
        if localize("ko", "en") != "ko" {
            if let error = error as? AntigravityUsageError {
                switch error {
                case .cliNotFound: return "Antigravity CLI was not found. Choose the agy executable or a usage report."
                case .unsupportedVersion: return "Antigravity CLI 1.1.11 or newer is required for read-only usage reports."
                case .timeout: return "Antigravity usage read timed out. Check the CLI and try again."
                case .commandFailed: return "Could not read Antigravity CLI usage. Check its sign-in and configuration, then retry."
                case .reportUnavailable: return "Choose a readable Antigravity usage JSON report."
                case .staleReport: return "This Antigravity report is over 15 minutes old or its allowance has reset. Export a new /usage report."
                case .futureReport: return "This Antigravity report has a future timestamp. Check the file and system clock."
                case .noWeeklyQuota: return "The Antigravity report did not provide a Gemini weekly allowance."
                case .invalidResponse: return "Could not read this Antigravity usage JSON report. Export a new /usage report."
                }
            }
        }
        if selectedProfile.provider != .codex { return error.localizedDescription }
        if localize("ko", "en") == "ko" { return error.localizedDescription }
        switch error as? UsageError {
        case .unsupportedProvider: return "This saved connection is unavailable in this build. Select Codex or Antigravity."
        case .notLoggedIn: return "Sign in with ChatGPT to view weekly usage."
        case .unsupportedAccount: return "API key accounts do not provide a ChatGPT weekly allowance."
        case .cliNotFound: return "Codex was not found. Choose the executable in connection settings."
        case .noWeeklyQuota: return "This account did not provide a weekly allowance."
        case .timeout, .loginTimeout: return "The request timed out. Try again."
        default: return "Could not read Codex usage. Check your connection and sign-in, then refresh."
        }
    }
}
