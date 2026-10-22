import AppPluginHost
import AppKit
import SwiftUI
import Combine
import EventKit
import ServiceManagement
import AfterSixCore
import MacLaunchSupport
import AppPluginCore

let runtimeProfile = AppRuntimeProfile(bundleIdentifier: Bundle.main.bundleIdentifier,
    applicationSupport: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0])

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let calendarSync = CalendarSyncModel(runtimeAllowed: false, storeURL: runtimeProfile.syncURL)
    private let pluginPresentations = PluginSettingsPresentationRegistry()
    private lazy var plugins: PluginManagerModel = {
        let manager = PluginManagerModel(defaultAdapter: DefaultFeatureAdapter(),
            routingStore: FeatureRoutingStore(url: runtimeProfile.routingURL),
            catalogStore: PluginCatalogStore(url: runtimeProfile.catalogURL))
        manager.configureCatalog(sync: calendarSync, presentations: pluginPresentations,
            allowsExternalIntegrations: runtimeProfile.allowsExternalIntegrations)
        return manager
    }()
    private lazy var model = AppModel(store: StateStore(url: runtimeProfile.stateURL), featureRouter: plugins.router,
        allowsLoginItemChanges: runtimeProfile.allowsLoginItemChanges)
    private lazy var featureCalendar = FeatureCalendarModel(router: plugins.router)
    private let updater = AppUpdater()
    private let settingsNavigation = SettingsNavigation()
    private var settingsWindow: NSWindow?
    private var observation: AnyCancellable?
    private var languageObservation: AnyCancellable?
    private var pluginObservation: AnyCancellable?
    private var imageObservation: AnyCancellable?
    private var statusAppearanceObservations: [NSKeyValueObservation] = []
    private var statusInteractionMonitor: Any?
    private var trackingStatusInteraction = false
    private var renderedStatusDark: Bool?
    private var renderedStatusHighlighted: Bool?
    private let menuBarImages = PluginMenuBarImageGroup()
    private var baseMenuBarImage = LuluBrand.menuBarIcon()
    private var baseToolTip = ""
    private var baseAccessibilityLabel = ""
    private var displayedMenuTitle = ""
    private var displayedPluginItems: [PluginMenuBarItem] = []

    private var displayedLuluState: LuluDisplayState?
    private var displayedVacationEve = false
    private var loginObservedAt: Date?

    func applicationWillFinishLaunching(_ notification: Notification) {
        observeLoginLaunch()
    }

    private func observeLoginLaunch() {
        if loginObservedAt == nil,
           LoginLaunch.isLoginItem(NSAppleEventManager.shared().currentAppleEvent) {
            loginObservedAt = Date()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        observeLoginLaunch()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = LuluBrand.menuBarIcon()
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self
            button.action = #selector(togglePanel)
            statusAppearanceObservations.append(button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.refreshStatusAppearance() }
            })
            statusInteractionMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { [weak self, weak button] event in
                guard let self, let button else { return event }
                if event.type == .leftMouseDown {
                    self.trackingStatusInteraction = event.window === button.window
                        && button.bounds.contains(button.convert(event.locationInWindow, from: nil))
                }
                guard self.trackingStatusInteraction else { return event }
                if event.type == .leftMouseUp { self.trackingStatusInteraction = false }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.popover.isShown { self.statusItem.button?.highlight(true) }
                    self.refreshStatusAppearance()
                }
                return event
            }
        }
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 364, height: 350)
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model, calendarSync: calendarSync, plugins: plugins, onOpenHistory: { [weak self] in
            self?.openSettings(section: .history)
        }, onOpenSettings: { [weak self] in
            self?.openSettings()
        }, onOpenCalendar: { [weak self] in
            self?.openSettings(section: .calendar)
        }, onOpenPlugin: { [weak self] id in
            self?.settingsNavigation.pluginID = id
            self?.openSettings(section: .plugin)
        }))
        observation = model.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
        pluginObservation = plugins.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.updateTitle() }
        }
        imageObservation = menuBarImages.changes.sink { [weak self] in self?.updateMenuBarImage() }
        languageObservation = AppLanguage.shared.$choice.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.updateTitle()
                self?.settingsWindow?.title = L("happylulu 설정", "happylulu Settings")
                NSApplication.shared.mainMenu = makeApplicationMenu()
            }
        }
        let firstLaunch = !model.state.didOfferLoginItem
        let hasLegacyAttendance = FileManager.default.fileExists(atPath: runtimeProfile.stateURL.path)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if runtimeProfile.allowsExternalIntegrations && self.plugins.needsLegacyMigration {
                do {
                    let calendarConfigured = try await self.calendarSync.legacyConfigured()
                    self.plugins.migrateLegacy(calendarConfigured: calendarConfigured,
                        daouConfigured: try BundledPlugins.legacyDaouConfigured(),
                        detectsHalfDays: self.model.state.detectHalfDaysFromCalendar,
                        hasLegacyAttendance: hasLegacyAttendance)
                } catch { self.plugins.reportMigrationFailure() }
            }
            self.model.observeFeatures(self.plugins)
            if runtimeProfile.allowsAutomaticActivity {
                self.model.start(loginObservedAt: self.loginObservedAt)
                self.plugins.start()
            }
        }
        updater.canInstallNow = { [weak self] in
            guard let self else { return false }
            return !self.model.isProcessingAttendance && !self.calendarSync.isRunning && !self.plugins.isRunning
                && !NSApplication.shared.isActive
                && !NSApplication.shared.windows.contains { $0.isVisible && $0.level == .normal }
        }
        if runtimeProfile.allowsAutomaticActivity { updater.start() }
        updateTitle()
        if firstLaunch { togglePanel() }
        if CommandLine.arguments.contains("--calendar") { openSettings(section: .calendar) }
        if CommandLine.arguments.contains("--plugins") { openSettings(section: .plugins) }
    }

    private func updateTitle() {
        if displayedLuluState != model.luluDisplayState || displayedVacationEve != model.isVacationEve {
            baseMenuBarImage = LuluBrand.menuBarIcon(for: model.luluDisplayState, vacationEve: model.isVacationEve)
            displayedLuluState = model.luluDisplayState
            displayedVacationEve = model.isVacationEve
        }
        let items = plugins.menuBarItems
        menuBarImages.setProviders(plugins.registrations.compactMap { entry in
            guard plugins.allowsExternalIntegrations, plugins.isEnabled(entry.id), entry.controller.enabled else { return nil }
            return entry.controller as? any PluginMenuBarImageProviding
        })
        displayedMenuTitle = model.menuTitle
        displayedPluginItems = items
        updateMenuBarTitle()
        let pluginPanelHeight = plugins.registrations.reduce(CGFloat.zero) { height, entry in
            guard plugins.allowsExternalIntegrations, plugins.isEnabled(entry.id), entry.controller.enabled,
                  let provider = entry.controller as? any PluginPanelProviding else { return height }
            return height + provider.panelHeight
        }
        popover.contentSize = NSSize(width: 364, height: CGFloat(350 + 40 * items.count) + pluginPanelHeight)
        var toolTip = model.departure.map { L("출근 \(model.timeLabel(model.arrival!.time)) · 퇴근 예정 \(model.timeLabel($0))", "Arrived \(model.timeLabel(model.arrival!.time)) · expected departure \(model.timeLabel($0))") }
            ?? (model.luluDisplayState == .waiting
                ? L("happylulu · 일반 06:00~10:00(08시 이전은 08시 기록), 오전 반차 13:00~15:00 로그인·잠금 해제를 기다립니다", "happylulu · waiting for login/unlock: regular 06:00–10:00 (before 08:00 recorded at 08:00), morning off 13:00–15:00")
                : model.luluStateLabel)
        if let extra = model.postDepartureStatus {
            if let elapsed = model.postDepartureText { toolTip += " · " + elapsed }
            toolTip += " · " + model.mealStatusLabel(extra)
            toolTip += " · " + L("예정 시각 기준, 실제 근무·지급 미확인",
                                   "Scheduled time only; work and payment unverified")
        }
        if !items.isEmpty { toolTip += " · " + items.map(\.accessibilityLabel).joined(separator: " · ") }
        baseToolTip = model.luluStateLabel + " · " + toolTip
        let accessibleTitle = ([model.menuTitle] + items.map(\.accessibilityLabel)).joined(separator: " · ")
        baseAccessibilityLabel = "happylulu, \(model.luluStateLabel), \(accessibleTitle)"
        updateMenuBarImage()
    }

    private func updateMenuBarTitle() {
        guard let button = statusItem.button else { return }
        button.attributedTitle = PluginMenuBarTitle.attributed(base: displayedMenuTitle, items: displayedPluginItems,
            font: button.font ?? .monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            appearance: button.effectiveAppearance, highlighted: button.cell?.isHighlighted == true)
    }

    private func updateMenuBarImage() {
        guard let button = statusItem.button else { return }
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let highlighted = button.cell?.isHighlighted == true
        let toneChanged = renderedStatusDark != dark || renderedStatusHighlighted != highlighted
        renderedStatusDark = dark
        renderedStatusHighlighted = highlighted
        if toneChanged { updateMenuBarTitle() }
        let base: NSImage
        if case .orbit(let phase, let palette) = menuBarImages.baseIconEffect {
            base = LuluBrand.menuBarIcon(for: model.luluDisplayState, vacationEve: model.isVacationEve,
                orbitPhase: phase, appearance: button.effectiveAppearance, highlighted: button.cell?.isHighlighted == true,
                palette: palette)
        } else {
            base = baseMenuBarImage
        }
        button.image = menuBarImages.image(base: base)
        let labels = menuBarImages.accessibilityLabels
        let suffix = labels.isEmpty ? "" : " · " + labels.joined(separator: " · ")
        let toolTip = baseToolTip + suffix
        let accessibilityLabel = baseAccessibilityLabel + suffix
        // Animation frames change only the image; sampled metadata updates accessibility.
        if button.toolTip != toolTip { button.toolTip = toolTip }
        if button.accessibilityLabel() != accessibilityLabel { button.setAccessibilityLabel(accessibilityLabel) }
    }

    private func refreshStatusAppearance() {
        guard let button = statusItem.button else { return }
        let dark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let highlighted = button.cell?.isHighlighted == true
        // AppKit can notify effectiveAppearance again when image changes; unchanged tones must not feed back.
        guard renderedStatusDark != dark || renderedStatusHighlighted != highlighted else { return }
        updateMenuBarImage()
    }

    @objc func togglePanel() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        model.refresh()
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        updateMenuBarImage()
    }

    func popoverDidShow(_ notification: Notification) {
        statusItem.button?.highlight(true)
        refreshStatusAppearance()
    }
    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
        refreshStatusAppearance()
    }

    private func openSettings(section: SettingsSection? = nil) {
        if let section { settingsNavigation.selection = section }
        if popover.isShown { popover.performClose(nil) }
        NSApplication.shared.setActivationPolicy(.regular)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = L("happylulu 설정", "happylulu Settings")
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(
                model: model, updater: updater, calendarSync: calendarSync, plugins: plugins,
                featureCalendar: featureCalendar, pluginPresentations: pluginPresentations, navigation: settingsNavigation))
            window.center()
            settingsWindow = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if updater.isInstallingUpdate && (model.isProcessingAttendance || calendarSync.isRunning || plugins.isRunning) {
            updater.installationWasDeferred()
            return .terminateCancel
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let statusInteractionMonitor { NSEvent.removeMonitor(statusInteractionMonitor) }
        plugins.stop(); calendarSync.setRuntimeAllowed(false)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === settingsWindow else { return }
        DispatchQueue.main.async { [weak self] in
            if self?.settingsWindow?.isVisible != true {
                NSApplication.shared.setActivationPolicy(.accessory)
            }
        }
    }
}

if CommandLine.arguments.contains("--runtime-profile") {
    print("development=\(runtimeProfile.isDevelopment)")
    print("externalIntegrations=\(runtimeProfile.allowsExternalIntegrations)")
    print("loginItemChanges=\(runtimeProfile.allowsLoginItemChanges)")
    print("automaticActivity=\(runtimeProfile.allowsAutomaticActivity)")
    print("state=\(runtimeProfile.stateURL.path)")
    print("routing=\(runtimeProfile.routingURL.path)")
    print("catalog=\(runtimeProfile.catalogURL.path)")
    print("sync=\(runtimeProfile.syncURL.path)")
    exit(0)
}

let calendarRuntimeFlags = CommandLine.arguments.filter {
    ["--calendar-preview", "--calendar-resume", "--calendar-runtime-check"].contains($0)
}
if !calendarRuntimeFlags.isEmpty {
    guard runtimeProfile.allowsExternalIntegrations else { exit(64) }
    guard calendarRuntimeFlags.count == 1 else { exit(64) }
    let mode: CalendarSyncRuntimeChecks.Mode
    switch calendarRuntimeFlags[0] {
    case "--calendar-preview": mode = .previewSelected
    case "--calendar-runtime-check": mode = .isolatedRoundtrip
    default:
        guard let index = CommandLine.arguments.firstIndex(of: "--reviewed-receipt"),
              index + 1 < CommandLine.arguments.count else { exit(64) }
        let receipt = CommandLine.arguments[index + 1]
        guard receipt.count == 64, receipt.allSatisfy({ $0.isHexDigit }) else { exit(64) }
        mode = .resumeSelected(reviewedReceipt: receipt)
    }
    Task { @MainActor in
        do {
            try await CalendarSyncRuntimeChecks.run(mode: mode)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("HappyLulu: calendar check could not produce a report.\n".utf8))
            exit(1)
        }
    }
    dispatchMain()
}

if CommandLine.arguments.contains("--calendar-diagnostics") {
    guard runtimeProfile.allowsExternalIntegrations else { exit(64) }
    // Runs before app models, timers, updater and single-instance activation.
    // Reads calendar diagnostics without requesting permission or writing events.
    do {
        try CalendarSyncDiagnostics.run()
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("HappyLulu: calendar diagnostics could not be read.\n".utf8))
        exit(1)
    }
}

if CommandLine.arguments.contains("--status") {
    // Read-only diagnostics; no notification injection or attendance mutation.
    do {
        let state = try StateStore(url: runtimeProfile.stateURL).load()
        let record = Attendance.today(in: state, now: Date(), calendar: .current)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        print("app=HappyLulu version=\(version)")
        print("loginItemStatus=\(SMAppService.mainApp.status.rawValue)")
        print("calendarAccessStatus=\(EKEventStore.authorizationStatus(for: .event).rawValue)")
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
        let publicKey = (info["SUPublicEDKey"] as? String).flatMap { Data(base64Encoded: $0) }
        print("updaterConfigured=\(feed?.scheme == "https" && publicKey?.count == 32)")
        print("updaterAutomaticChecksDefault=\(info["SUEnableAutomaticChecks"] as? Bool ?? false)")
        print("updaterAutomaticInstallationDefault=\(info["SUAutomaticallyUpdate"] as? Bool ?? false)")
        print("todayRecorded=\(record != nil)")
        print("lastUnlockObserved=\(state.lastUnlockAt != nil)")
        print("workMinutes=\(state.settings.workMinutes) breakMinutes=\(state.settings.breakMinutes)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("HappyLulu: state could not be read.\n".utf8))
        exit(1)
    }
}

if CommandLine.arguments.contains("--plugin-modules") {
    // Composition diagnostics only: no controller, Keychain, attendance or timers are created.
    print(BundledPlugins.modules.map { $0.id }.joined(separator: ","))
    exit(0)
}

let application = NSApplication.shared
if let identifier = Bundle.main.bundleIdentifier,
   let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
    existing.activate(options: [.activateIgnoringOtherApps])
    exit(0)
}
let delegate = AppDelegate()
application.setActivationPolicy(.accessory)
// Manual NSApplication startup does not install SwiftUI's standard editing commands.
application.mainMenu = makeApplicationMenu()
application.delegate = delegate
application.run()
