import AppKit
import SwiftUI
import AppPluginCore
import AppPluginHost
import AfterSixCore
import AIUsagePlugin
import AIUsageIntegration
import CPURunnerIntegration

private func reportUsageProbe(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private struct PreviewUsageProvider: UsageProvider {
    let name = "Codex"
    func fetch() async throws -> UsageSnapshot {
        UsageSnapshot(weekly: UsageWindow(usedPercent: 28, windowDurationMins: 10080,
            resetsAt: Date().addingTimeInterval(5 * 86400).timeIntervalSince1970), accountKey: "synthetic-fixture")
    }
    func makeLoginAttempt() -> (any UsageLoginAttempt)? { nil }
}

@MainActor
private enum PreviewUsageModule: PluginModule {
    static let id = AIUsageModule.id
    static var catalogMetadata: PluginModuleMetadata? { AIUsageModule.catalogMetadata }
    static var model: AIUsageModel!
    static let iconSource = "official-monochrome-glyph"
    static func register(in context: PluginHostContext) throws {
        let model = AIUsageModel(localize: context.localize, providerFactory: { _ in PreviewUsageProvider() })
        model.updatePreferences { $0.labelFormat = .icon }
        precondition(model.menuBarPreview.iconPNG != nil && model.menuBarPreview.iconIsTemplate,
            "The production Codex glyph must render; a synthetic icon cannot validate it")
        self.model = model
        let adapter = SnapshotFeatureAdapter(descriptor: FeatureAdapterDescriptor(id: id, name: id, features: []),
            api: context.registry, timeZone: .current)
        try context.register(PluginRegistration(controller: model, adapter: adapter, symbol: "gauge", summary: "Fixture",
            setEnabled: model.setEnabled))
        try context.presentations.register(id) { AIUsageSettingsView(model: model) }
    }
}

@MainActor
private final class PreviewRunnerScheduledTask: RunnerScheduledTask {
    func cancel() {}
}

@MainActor
private enum PreviewRunnerModule: PluginModule {
    static let id = CPURunnerModule.id
    static var model: CPURunnerController!
    static var advanceSample: (() -> Void)!

    static func register(in context: PluginHostContext) throws {
        var ticks: UInt64 = 0
        var sampleTime: TimeInterval = 0
        let metrics = SystemMetricsSampler(readers: SystemMetricsReaders(memory: {
            MemoryMetrics(totalBytes: 32 * 1_024 * 1_024 * 1_024, usedBytes: 12 * 1_024 * 1_024 * 1_024, pressure: .normal)
        }, storage: {
            StorageMetrics(totalBytes: 1_000_000_000_000, availableBytes: 640_000_000_000)
        }, network: {
            [NetworkInterfaceCounters(name: "en0", index: 4, isConnected: true,
                receivedBytes: 1_000 + UInt64(sampleTime * 8_500_000), sentBytes: 2_000 + UInt64(sampleTime * 1_200_000))]
        }, battery: {
            BatteryMetrics(presence: .present, percent: 76, isCharging: true, isExternalPower: true)
        }), now: { sampleTime })
        let model = CPURunnerController(settings: RunnerSettings(), sampler: CPUUsageSampler(readTicks: {
            ticks += 1
            return CPUUsageTicks(user: ticks * 35, system: 0, nice: 0, idle: ticks * 65)
        }), metricsSampler: metrics, schedule: { _, _ in PreviewRunnerScheduledTask() },
            reduceMotion: { false }, lowPower: { false }, observeSystemChanges: false, localize: context.localize)
        model.selectAnimal(.cat)
        model.selectPresentation(.animal)
        self.model = model
        advanceSample = { sampleTime += 1; model.refreshData() }
        let adapter = SnapshotFeatureAdapter(descriptor: FeatureAdapterDescriptor(id: id, name: id, features: []),
            api: context.registry, timeZone: .current)
        try context.register(PluginRegistration(controller: model, adapter: adapter, symbol: "pawprint", summary: "Fixture",
            setEnabled: model.setModuleEnabled))
        try context.presentations.register(id) { CPURunnerSettingsView(model: model, localize: context.localize) }
    }
}

@MainActor
private final class UsageProbeDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        reportUsageProbe("BEGIN usage UI applicationDidFinishLaunching")
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor in
            do { try await AIUsageUIProbe.check(); exit(0) }
            catch { print("FAIL usage UI: \(error)"); exit(1) }
        }
    }
}

@MainActor
private final class UsageMenuObservation: NSObject {
    var menu: NSMenu?
    @objc func didBeginTracking(_ notification: Notification) {
        menu = notification.object as? NSMenu
        reportUsageProbe("BEGIN usage menu tracking")
        // A synchronous menu loop may run inside the main-queue Task below.
        // Schedule in its tracking mode so cancellation does not need queue reentry.
        menu?.perform(#selector(NSMenu.cancelTracking), with: nil, afterDelay: 0,
                      inModes: [.eventTracking, .default])
    }
}

@MainActor
private final class UsageRoutingObservation { var openedPlugin: String? }

@main
struct AIUsageUIProbe {
    @MainActor static func main() {
        reportUsageProbe("BEGIN usage UI app")
        let app = NSApplication.shared
        let delegate = UsageProbeDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor static func check() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        precondition(Bundle.main.bundleIdentifier!.hasPrefix("local.happylulu.usage-probe."))
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.mainMenu = makeApplicationMenu()
        precondition(Bundle.main.url(forResource: "HappyLuluBrand", withExtension: "png") != nil)
        for state in LuluDisplayState.allCases {
            precondition(Bundle.main.url(forResource: state.rawValue, withExtension: "png", subdirectory: "OwlStates") != nil)
        }
        let runnerBundleURL = Bundle.main.resourceURL!.appendingPathComponent("HappyLulu_CPURunnerIntegration.bundle")
        let runnerBundle = Bundle(url: runnerBundleURL)!
        for frame in 0..<5 {
            precondition(runnerBundle.url(forResource: "cat\(frame)", withExtension: "png", subdirectory: "RunCat") != nil)
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!) }
        AppLanguage.shared.select(.korean)
        let store = StateStore(url: output.appendingPathComponent("attendance.json"))
        var state = AttendanceState(); state.didOfferLoginItem = true; state.detectHalfDaysFromCalendar = false
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 12))!
        var now = noon
        let day = Attendance.dayKey(now, calendar: calendar)
        let arrival = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        state.arrivals[day] = Arrival(day: day, time: arrival, source: .manual,
            timeZoneID: calendar.timeZone.identifier, modeSource: .manual)
        try store.save(state)
        let before = try Data(contentsOf: store.url)
        let sync = CalendarSyncModel(runtimeAllowed: false, storeURL: output.appendingPathComponent("calendar.sqlite"))
        let plugins = PluginManagerModel(defaultAdapter: DefaultFeatureAdapter(),
            routingStore: FeatureRoutingStore(url: nil), catalogStore: PluginCatalogStore(url: nil))
        let presentations = PluginSettingsPresentationRegistry()
        plugins.configureCatalog(sync: sync, presentations: presentations, modules: [PreviewUsageModule.self, PreviewRunnerModule.self])
        plugins.start()
        plugins.install(PreviewRunnerModule.id); plugins.setEnabled(PreviewRunnerModule.id, true)
        PreviewRunnerModule.advanceSample()
        precondition(PreviewRunnerModule.model.animal == .cat && PreviewRunnerModule.model.usage == 0.35)
        precondition(PreviewRunnerModule.model.metrics.memory != nil && PreviewRunnerModule.model.metrics.storage != nil
            && PreviewRunnerModule.model.metrics.network?.receivedBytesPerSecond == 8_500_000
            && PreviewRunnerModule.model.metrics.battery?.percent == 76)
        let model = AppModel(store: store, featureRouter: plugins.router, allowsLoginItemChanges: false,
            nowProvider: { now }, calendarProvider: { calendar })
        let navigation = SettingsNavigation()
        let settings = SettingsView(model: model, updater: AppUpdater(), calendarSync: sync, plugins: plugins,
            featureCalendar: FeatureCalendarModel(router: plugins.router), pluginPresentations: presentations, navigation: navigation)
        let routing = UsageRoutingObservation()
        let panel = PanelView(model: model, calendarSync: sync, plugins: plugins,
            onOpenHistory: {}, onOpenSettings: {}, onOpenPlugin: { routing.openedPlugin = $0 })
        var variants: [(AppearancePalette, ColorScheme, String)] = [(.softMint, .light, "light"), (.charcoal, .dark, "dark")]
        if AppearanceModel.supportsNativeAppearance {
            variants += [(.nativeGlass, .light, "native-light"), (.nativeGlass, .dark, "native-dark")]
        }
        for (theme, scheme, suffix) in variants {
            application.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            AppearanceModel.shared.selectPalette(theme)
            navigation.selection = .general
            plugins.setShowUsage(false)
            try await render(settings, size: NSSize(width: 920, height: 720), name: "general-off-" + suffix,
                directory: output, scheme: scheme)
            try await render(settings, size: NSSize(width: 820, height: 620), name: "general-off-minimum-" + suffix,
                directory: output, scheme: scheme)
            plugins.setShowUsage(true)
            let deadline = Date().addingTimeInterval(3)
            while PreviewUsageModule.model.snapshot == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            PreviewUsageModule.model.updatePreferences { $0.labelFormat = .named }
            precondition(plugins.menuBarItems.first?.title == "Codex 72%")
            try await render(settings, size: NSSize(width: 820, height: 620), name: "general-on-minimum-" + suffix,
                directory: output, scheme: scheme)
            navigation.pluginID = AIUsageModule.id; navigation.selection = .plugin
            try await render(settings, size: NSSize(width: 820, height: 700), name: "usage-settings-" + suffix,
                directory: output, scheme: scheme)
            try await render(settings, size: NSSize(width: 820, height: 980), name: "usage-connection-expanded-" + suffix,
                directory: output, scheme: scheme)
            PreviewUsageModule.model.updatePreferences { $0.labelFormat = .icon }
            precondition(plugins.menuBarItems.first?.title == "72%" && plugins.menuBarItems.first?.iconPNG != nil
                && plugins.menuBarItems.first?.iconIsTemplate == true)
            try await render(settings, size: NSSize(width: 820, height: 700), name: "usage-settings-icon-" + suffix,
                directory: output, scheme: scheme)
            precondition(plugins.panelProviders.count == 1 && plugins.panelProviders[0].panelHeight == 184)
            routing.openedPlugin = nil
            try await render(panel, size: NSSize(width: 364, height: 574), name: "panel-" + suffix,
                directory: output, scheme: scheme, routing: routing)
            precondition(routing.openedPlugin == AIUsageModule.id, "Usage row must open its plugin settings")
            PreviewRunnerModule.model.selectPresentation(.animal)
            try await renderStatusButton(model: model, plugins: plugins, directory: output, scheme: scheme, variantSuffix: suffix)
            PreviewRunnerModule.model.selectPresentation(.owlOrbit)
            precondition(PreviewRunnerModule.model.menuBarImage == nil && PreviewRunnerModule.model.baseIconEffect != nil)
            navigation.pluginID = CPURunnerModule.id; navigation.selection = .plugin
            try await render(settings, size: NSSize(width: 820, height: 760), name: "owl-settings-" + suffix,
                directory: output, scheme: scheme)
            try await renderStatusButton(model: model, plugins: plugins, directory: output, scheme: scheme, variantSuffix: suffix)
            PreviewRunnerModule.model.setOrbitPalette(PluginOrbitPalette(startRGB: 0xFF7A59, endRGB: 0xFFC857))
            try await render(settings, size: NSSize(width: 820, height: 760), name: "owl-colors-custom-" + suffix,
                directory: output, scheme: scheme)
            PreviewRunnerModule.model.setOrbitPalette(.standard)
            let savedDisplay = model.countdownDisplay
            let savedDepartureVisibility = model.showDepartureInMenuBar
            let departure = model.departure!
            model.setCountdownDisplay(.hoursMinutes)
            model.setShowDepartureInMenuBar(true)
            for minute in [90, 91] {
                now = departure.addingTimeInterval(Double(minute * 60))
                model.refresh()
                let elapsed = "추가 1시간 \(minute - 60)분 중"
                precondition(model.postDepartureText == elapsed && model.menuTitle == "퇴근 18:00 · " + elapsed)
                try await render(panel, size: NSSize(width: 364, height: 574), name: "overtime-\(minute)-" + suffix,
                    directory: output, scheme: scheme)
                try await renderStatusButton(model: model, plugins: plugins, directory: output, scheme: scheme, variantSuffix: suffix,
                    namePrefix: "overtime-\(minute)-")
            }
            now = noon
            model.setCountdownDisplay(savedDisplay)
            model.setShowDepartureInMenuBar(savedDepartureVisibility)
        }
        plugins.setShowUsage(false); plugins.setEnabled(PreviewRunnerModule.id, false); plugins.stop()
        precondition(plugins.menuBarItems.isEmpty && !PreviewUsageModule.model.isRunning
            && PreviewRunnerModule.model.menuBarImage == nil && PreviewRunnerModule.model.baseIconEffect == nil
            && PreviewRunnerModule.model.metrics == .empty)
        let after = try Data(contentsOf: store.url)
        precondition(before == after && !sync.runtimeAllowed)
        print("PASS usage UI: actual settings/full attendance panel, isolated synthetic 72%/CPU35%/memory/storage/network/battery, expanded Codex connection, owl orbit and cat, light/dark, minimum settings size, packaged runner assets, display-off, stop and unchanged attendance")
        print("PASS native status button: owl orbit without extra animal, preserved owl/cat group, inline Codex icon/72%, aqua/darkAqua, native highlight flags, \(PreviewUsageModule.iconSource)")
        print("PASS overtime presentation: injected clock advances 90 to 91 minutes, shared elapsed text in panel/menu, light/dark, unchanged attendance")
        print("PASS usage panel: existing/native light/dark, 574pt metrics panel, usage-row routing and Settings/Quit menu")
        print("LIMIT native status button: cached button views do not capture the window-managed selection background")
    }

    @MainActor private static func renderStatusButton(model: AppModel, plugins: PluginManagerModel,
        directory: URL, scheme: ColorScheme, variantSuffix: String, namePrefix: String = "") async throws {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = item.button!
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
        button.appearance = appearance
        let group = PluginMenuBarImageGroup()
        group.setProviders([PreviewRunnerModule.model])
        let orbit = PreviewRunnerModule.model.presentation == .owlOrbit
        let presentationName = orbit ? "owl" : "animal"
        func renderImage(highlighted: Bool) -> NSImage {
            let base: NSImage
            if case let .orbit(phase, palette)? = group.baseIconEffect {
                base = LuluBrand.menuBarIcon(for: model.luluDisplayState, vacationEve: model.isVacationEve,
                    orbitPhase: phase, appearance: appearance, highlighted: highlighted, palette: palette)
            } else {
                base = LuluBrand.menuBarIcon(for: model.luluDisplayState, vacationEve: model.isVacationEve)
            }
            return group.image(base: base)
        }
        button.image = renderImage(highlighted: false)
        precondition(button.image?.size == NSSize(width: orbit ? 26 : 58, height: 18))
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        button.attributedTitle = PluginMenuBarTitle.attributed(base: model.menuTitle,
            items: plugins.menuBarItems, font: button.font!, appearance: appearance)
        precondition(button.attributedTitle.string.contains("72%") && !button.attributedTitle.string.contains("Codex"))
        var attachments = 0
        button.attributedTitle.enumerateAttribute(.attachment,
            in: NSRange(location: 0, length: button.attributedTitle.length)) { value, _, _ in
                if value is NSTextAttachment { attachments += 1 }
            }
        precondition(attachments == 1)
        button.setAccessibilityLabel("happylulu, " + model.menuTitle + " · "
            + plugins.menuBarItems.map(\.accessibilityLabel).joined(separator: " · ")
            + " · " + group.accessibilityLabels.joined(separator: " · "))
        button.sizeToFit()
        item.length = ceil(button.frame.width)
        for highlighted in [false, true] {
            button.needsDisplay = true
            try await Task.sleep(for: .milliseconds(80))
            button.layoutSubtreeIfNeeded()
            guard let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) else { fatalError("No status button bitmap") }
            appearance.performAsCurrentDrawingAppearance {
                button.highlight(highlighted)
                button.image = renderImage(highlighted: highlighted)
                button.attributedTitle = PluginMenuBarTitle.attributed(base: model.menuTitle,
                    items: plugins.menuBarItems, font: button.font!, appearance: appearance, highlighted: highlighted)
                precondition(button.cell?.isHighlighted == highlighted)
                button.cacheDisplay(in: button.bounds, to: bitmap)
            }
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No status button PNG") }
            let name = namePrefix + "status-button-\(presentationName)-\(variantSuffix)-\(highlighted ? "highlighted" : "normal")"
            try png.write(to: directory.appendingPathComponent(name + ".png"))
            let native = NSImage(size: button.bounds.size)
            native.addRepresentation(bitmap)
            let preview = NSImage(size: button.bounds.size, flipped: false) { rect in
                appearance.performAsCurrentDrawingAppearance {
                    NSColor.windowBackgroundColor.setFill(); rect.fill()
                    native.draw(in: rect)
                }
                return true
            }
            let previewPNG = NSBitmapImageRep(data: preview.tiffRepresentation!)!.representation(using: .png, properties: [:])!
            try previewPNG.write(to: directory.appendingPathComponent(name + "-on-surface.png"))
        }
    }
    @MainActor private static func render<V: View>(_ view: V, size: NSSize, name: String,
        directory: URL, scheme: ColorScheme, routing: UsageRoutingObservation? = nil) async throws {
        reportUsageProbe("BEGIN usage render: \(name)")
        let materialMode: LuluMaterialMode =
            ProcessInfo.processInfo.environment["HAPPY_LULU_MATERIAL_MODE"] == "legacy" ? .legacy : .automatic
        let controller = NSHostingController(rootView: view.environment(\.luluMaterialMode, materialMode))
        let isPanel = name.hasPrefix("panel-") || name.hasPrefix("overtime-")
        let window: NSWindow = isPanel && LuluGlass.isSupported
            ? MenuBarPanel(content: controller, size: size)
            : NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                       styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(size)
        let chrome = isPanel ? nil : SettingsWindowChrome(window: window, appearance: .shared)
        defer { withExtendedLifetime(chrome) {}; window.orderOut(nil); window.contentViewController = nil; window.close() }
        let host = controller.view
        let live = ProcessInfo.processInfo.environment["HAPPY_LULU_USAGE_LIVE"] == "1"
            && name.contains("native-") && !name.hasPrefix("general-")
        if live { window.center() }
        else { window.setFrameOrigin(NSPoint(x: -10000, y: -10000)) }
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
        window.effectiveAppearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: bitmap) }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        if live && CGPreflightScreenCaptureAccess() {
            let screenshot = directory.appendingPathComponent(name + ".window.png")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-o", "-l", String(window.windowNumber), screenshot.path]
            try process.run(); process.waitUntilExit()
            precondition(process.terminationStatus == 0)
            print("PASS usage live capture: \(screenshot.lastPathComponent)")
        }
        if let routing {
            let point = host.convert(NSPoint(x: 180, y: 251), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                window.sendEvent(event)
            }
            try await Task.sleep(for: .milliseconds(50))
            precondition(routing.openedPlugin == AIUsageModule.id, "Usage row click must reach the plugin callback")
            // AppKit menu placement requires an on-screen anchor, even when
            // the rest of this synthetic fixture is rendered offscreen.
            window.center()
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(100))
            let menuObservation = UsageMenuObservation()
            NotificationCenter.default.addObserver(menuObservation, selector: #selector(UsageMenuObservation.didBeginTracking(_:)),
                name: NSMenu.didBeginTrackingNotification, object: nil)
            defer { NotificationCenter.default.removeObserver(menuObservation) }
            let menuPoint = host.convert(NSPoint(x: 334, y: 30), to: nil)
            reportUsageProbe("BEGIN usage menu click: \(name)")
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: menuPoint, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
                window.sendEvent(event)
            }
            reportUsageProbe("END usage menu dispatch: \(name)")
            try await Task.sleep(for: .milliseconds(50))
            let menuTitles = menuObservation.menu?.items.filter { !$0.isSeparatorItem }.map(\.title)
            precondition(menuTitles == ["설정", "종료"],
                         "Settings/Quit menu missing for \(name): \(String(describing: menuTitles)); visible=\(window.isVisible), key=\(window.isKeyWindow)")
            print("PASS usage panel menu and routing: \(name)")
        }
        reportUsageProbe("PASS usage render: \(name)")
    }
}
