import AppKit
import SwiftUI
import AfterSixCore
import AppPluginHost
import AppPluginCore

struct AppearanceFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct GeneralFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct UsageControlFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct SettingsPageFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

@MainActor
private enum UsageFixtureModule: PluginModule {
    static let id = "ai-usage"
    static var catalogMetadata: PluginModuleMetadata? {
        PluginModuleMetadata(name: "AI 사용량", englishName: "AI Usage", author: "Fixture",
            summary: "Fixture", englishSummary: "Fixture", symbol: "gauge", providesUsage: true)
    }
    static func register(in context: PluginHostContext) throws {
        let controller = LocalPluginController(id: id, name: "AI Usage")
        let adapter = SnapshotFeatureAdapter(descriptor: FeatureAdapterDescriptor(id: id, name: "AI Usage", features: []),
            api: context.registry, timeZone: .current)
        try context.register(PluginRegistration(controller: controller, adapter: adapter, symbol: "gauge", summary: "Fixture",
            setEnabled: controller.setEnabled))
    }
}

@MainActor
private final class AppearanceFramesObservation {
    var frames: [String: CGRect] = [:]
}

private func sameFrame(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    abs(lhs.minX - rhs.minX) < 1 && abs(lhs.minY - rhs.minY) < 1
        && abs(lhs.width - rhs.width) < 1 && abs(lhs.height - rhs.height) < 1
}

private func controlsAlign(_ titles: [String], in frames: [String: CGRect]) -> Bool {
    let rows = titles.compactMap { frames[$0] }
    let controls = titles.compactMap { frames["control:" + $0] }
    guard rows.count == titles.count, controls.count == titles.count, let first = controls.first else { return false }
    return zip(rows, controls).allSatisfy { row, control in
        control.width > 0 && control.height > 0
            && control.minX >= row.minX && control.maxX <= row.maxX
            && control.minY >= row.minY && control.maxY <= row.maxY
            && abs(control.maxX - first.maxX) < 1
    }
}

@MainActor
private final class MaterialObservation {
    var enabled: Bool?
}

@MainActor
private struct MaterialObserver: View {
    private var glass = LuluGlass()
    let observation: MaterialObservation

    init(observation: MaterialObservation) {
        self.observation = observation
    }
    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .onAppear { observation.enabled = glass.isEnabled }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private func requestedMaterialMode() -> LuluMaterialMode {
    switch ProcessInfo.processInfo.environment["HAPPY_LULU_MATERIAL_MODE"] ?? "automatic" {
    case "automatic": .automatic
    case "legacy": .legacy
    default: fatalError("HAPPY_LULU_MATERIAL_MODE must be automatic or legacy")
    }
}

@MainActor
private func pump(_ host: NSView) {
    RunLoop.current.run(until: Date().addingTimeInterval(0.08))
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
}

@MainActor
private func click(_ point: NSPoint, in host: NSView, window: NSWindow, tracksMouse: Bool = false) {
    let location = host.convert(point, to: nil)
    let events = [NSEvent.EventType.leftMouseDown, .leftMouseUp].map { type in
        NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
    }
    if tracksMouse {
        // A native table may consume mouseUp in its synchronous mouseDown tracking loop.
        NSApp.postEvent(events[1], atStart: true)
        window.sendEvent(events[0])
        if let release = NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true) {
            window.sendEvent(release)
        }
    } else {
        events.forEach { window.sendEvent($0) }
    }
    pump(host)
}

@MainActor
private func tables(in view: NSView) -> [NSTableView] {
    (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap { tables(in: $0) }
}

@MainActor
private func scrollViews(in view: NSView) -> [NSScrollView] {
    (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
}

@MainActor
private func arrow(_ keyCode: UInt16, character: Int, host: NSView, window: NSWindow) {
    let characters = String(UnicodeScalar(character)!)
    for type in [NSEvent.EventType.keyDown, .keyUp] {
        let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode)!
        window.sendEvent(event)
    }
    pump(host)
}

@MainActor
private func bitmap(_ host: NSView) -> NSBitmapImageRep {
    host.layoutSubtreeIfNeeded()
    let result = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: result)
    return result
}

@main
struct SettingsNavigationProbe {
    @MainActor static func main() {
        precondition(Bundle.main.bundleIdentifier == nil, "Headless checks must not run from an app bundle")
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        do { try check() }
        catch { print("FAIL settings navigation: \(error)"); exit(1) }
    }

    @MainActor static func check() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        UserDefaults.standard.setVolatileDomain([AppLanguage.key: "english"], forName: UserDefaults.argumentDomain)
        let store = StateStore(url: root.appendingPathComponent("attendance.json"))
        var state = AttendanceState()
        state.didOfferLoginItem = true
        state.detectHalfDaysFromCalendar = false
        try store.save(state)
        let original = try Data(contentsOf: store.url)
        let sync = CalendarSyncModel(runtimeAllowed: false, storeURL: root.appendingPathComponent("sync.sqlite"))
        let catalogStore = PluginCatalogStore(url: root.appendingPathComponent("catalog.json"))
        let plugins = PluginManagerModel(defaultAdapter: DefaultFeatureAdapter(),
            routingStore: FeatureRoutingStore(url: nil), catalogStore: catalogStore)
        let presentations = PluginSettingsPresentationRegistry()
        plugins.configureCatalog(sync: sync, presentations: presentations, modules: [UsageFixtureModule.self],
            allowsExternalIntegrations: false, isolatedPluginIDs: [UsageFixtureModule.id])
        plugins.install("mac-calendar")
        plugins.install("leave-detection")
        let model = AppModel(store: store, featureRouter: plugins.router, allowsLoginItemChanges: false)
        let navigation = SettingsNavigation()
        let materialObservation = MaterialObservation()
        let appearanceFrames = AppearanceFramesObservation()
        let generalFrames = AppearanceFramesObservation()
        let usageFrames = AppearanceFramesObservation()
        let pageFrames = AppearanceFramesObservation()
        let view = SettingsView(model: model, updater: AppUpdater(), calendarSync: sync, plugins: plugins,
            featureCalendar: FeatureCalendarModel(router: plugins.router), pluginPresentations: presentations,
            navigation: navigation)
            .coordinateSpace(name: "appearance-layout")
            .onPreferenceChange(AppearanceFramesKey.self) { appearanceFrames.frames = $0 }
            .onPreferenceChange(GeneralFramesKey.self) { generalFrames.frames = $0 }
            .onPreferenceChange(UsageControlFramesKey.self) { usageFrames.frames = $0 }
            .onPreferenceChange(SettingsPageFramesKey.self) { pageFrames.frames = $0 }
            .overlay(alignment: .bottomTrailing) { MaterialObserver(observation: materialObservation) }
            .environment(\.luluMaterialMode, requestedMaterialMode())
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Settings fixture"
        let chrome = SettingsWindowChrome(window: window, appearance: .shared, mode: requestedMaterialMode())
        defer { withExtendedLifetime(chrome) {} }
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.setContentSize(NSSize(width: 820, height: 620))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        pump(host)
        precondition(abs(host.bounds.width - 820) < 1, "General settings fixture must use the minimum 820pt width")
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        let accessories = window.titlebarAccessoryViewControllers
        precondition(accessories.count == 1 && accessories[0].layoutAttribute == .left,
            "Brand must use the native titlebar position beside window controls")
        precondition(window.title == "Settings fixture", "The accessible window title must remain intact")
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
        precondition(buttons.count == 3, "All native window controls must remain available")
        let brandFrame = accessories[0].view.convert(accessories[0].view.bounds, to: nil)
        let buttonFrames = buttons.map { $0.convert($0.bounds, to: nil) }
        precondition(brandFrame.width > 0 && buttonFrames.allSatisfy { !$0.intersects(brandFrame) },
            "Titlebar brand must not overlap the window controls")
        precondition(brandFrame.minX >= buttonFrames.map(\.maxX).max()! - 1,
            "Titlebar brand must follow the window controls")
        precondition(accessories[0].view.hitTest(NSPoint(x: 5, y: 5)) == nil,
            "Brand must not intercept titlebar dragging")
        print("PASS titlebar accessory: follows three native controls, no overlap, drag passthrough, accessible title retained")
        guard let glassEnabled = materialObservation.enabled else {
            fatalError("Hosted material environment must be observed before selecting click coordinates")
        }
        func measure(_ name: String, change: () -> Void) {
            let start = DispatchTime.now().uptimeNanoseconds
            change()
            RunLoop.current.run(until: Date().addingTimeInterval(0.001))
            _ = bitmap(host)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            print(String(format: "MEASURE %@ %.2f ms", name, ms))
        }
        print("Fixture OS: \(ProcessInfo.processInfo.operatingSystemVersionString); Liquid Glass: \(glassEnabled)")
        let appearance = AppearanceModel.shared
        var failures = [String]()
        var baselineRows: [CGRect]?
        var baselineGeneral: [String: CGRect]?
        var baselineTitle: CGRect?
        let generalTitles = ["Language", "Countdown display", "Show expected departure in menu bar", "Launch at login"]
        for palette in AppearancePalette.allCases {
            appearance.selectPalette(palette)
            navigation.selection = .general
            navigation.pluginID = nil
            pump(host)
            let frames = generalFrames.frames
            let settingsWithControls = generalTitles + ["Current version"]
            if !controlsAlign(settingsWithControls, in: frames) {
                failures.append("\(palette.rawValue): General and Updates controls must share a right edge and fit their rows: \(frames)")
            }
            if let title = pageFrames.frames["title:General"], let viewport = pageFrames.frames["page-content"],
               let updates = pageFrames.frames["updates"] {
                // Full-size content draws the fixed title inside AppKit's top safe area.
                if title.maxY > viewport.minY || title.minY < -host.safeAreaInsets.top - 1
                    || abs(title.height - 44) > 1 || updates.minY <= (frames["Launch at login"]?.maxY ?? .infinity) {
                    failures.append("\(palette.rawValue): title must precede content; updates must follow General: title=\(title), viewport=\(viewport), updates=\(updates), rows=\(frames), safeArea=\(host.safeAreaInsets)")
                }
                if let baselineTitle, !sameFrame(baselineTitle, title) {
                    failures.append("\(palette.rawValue): page title geometry changed")
                }
                baselineTitle = title
            } else {
                failures.append("\(palette.rawValue): missing General title, viewport or merged Updates")
            }
            if frames["Show usage"] != nil || !usageFrames.frames.isEmpty {
                failures.append("\(palette.rawValue): usage control must not be in General")
            }
            let orderedGeneral = generalTitles.compactMap { frames[$0] }
            if orderedGeneral.count != generalTitles.count {
                failures.append("\(palette.rawValue): missing general settings rows")
            } else {
                let aligned = orderedGeneral.allSatisfy { abs($0.minX - orderedGeneral[0].minX) < 1 && abs($0.width - orderedGeneral[0].width) < 1 }
                let separated = zip(orderedGeneral, orderedGeneral.dropFirst()).allSatisfy { first, second in first.maxY <= second.minY }
                let fits = orderedGeneral.allSatisfy { $0.minX >= 0 && $0.maxX <= host.bounds.width && $0.maxY <= host.bounds.height }
                if !aligned || !separated || !fits { failures.append("\(palette.rawValue): general rows overlap, misalign, or exceed the minimum host") }
                if let baselineGeneral {
                    let matches = generalTitles.allSatisfy { sameFrame(baselineGeneral[$0]!, frames[$0]!) }
                    if !matches { failures.append("\(palette.rawValue): general row geometry changed") }
                    print("\(matches ? "PASS" : "FAIL") \(palette.rawValue): same four general rows")
                } else {
                    baselineGeneral = frames
                    print("PASS \(palette.rawValue): captured four general rows")
                }
            }
            let matchingTables = tables(in: host)
            guard matchingTables.count == 1, let table = matchingTables.first else {
                failures.append("\(palette.rawValue): expected one sidebar list, got \(matchingTables.count)")
                continue
            }
            let contentRows = (0..<table.numberOfRows).filter {
                table.rowView(atRow: $0, makeIfNecessary: true)?.isGroupRowStyle == false
            }
            let geometry = contentRows.map { table.rect(ofRow: $0) }
            guard geometry.count == 6 else {
                failures.append("\(palette.rawValue): expected six content rows after merging updates/history, got \(geometry.count)")
                continue
            }
            if palette == .nativeGlass {
                let destinations: [(SettingsSection, String?)] = [
                    (.general, nil), (.appearance, nil), (.work, nil),
                    (.plugins, nil), (.plugin, "mac-calendar"), (.plugin, "leave-detection")
                ]
                for (row, destination) in zip(contentRows, destinations) {
                    navigation.selection = destination.0 == .general ? .appearance : .general
                    navigation.pluginID = nil
                    pump(host)
                    table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    pump(host)
                    let passed = navigation.selection == destination.0 && navigation.pluginID == destination.1
                    if !passed { failures.append("navigation to \(destination.0.rawValue) / \(destination.1 ?? "none")") }
                    let title = destination.1.flatMap { id in plugins.catalog.first { $0.id == id }?.name }
                        ?? (destination.0 == .plugins ? "Manage plugins" : destination.0.title)
                    if pageFrames.frames["title:\(title)"] == nil {
                        failures.append("Page title must follow sidebar destination: \(title)")
                    }
                    if destination.0 == .work && pageFrames.frames["history"] == nil {
                        failures.append("Work must include arrival history")
                    }
                    print("\(passed ? "PASS" : "FAIL") sidebar selection -> \(destination.0.rawValue) / \(destination.1 ?? "none")")
                }
            }
            if let baselineRows {
                let matches = zip(baselineRows, geometry).allSatisfy { expected, actual in
                    abs(expected.minY - actual.minY) < 1 && abs(expected.height - actual.height) < 1
                        && abs(expected.width - actual.width) < 1
                }
                if !matches { failures.append("\(palette.rawValue): sidebar row geometry changed") }
                print("\(matches ? "PASS" : "FAIL") \(palette.rawValue): same six sidebar rows and geometry")
            } else {
                baselineRows = geometry
                print("PASS \(palette.rawValue): six sidebar rows")
            }
        }
        appearance.selectPalette(.nativeGlass)
        for (destination, title, sidebarIndex) in [(SettingsSection.history, "Work", 2), (.updates, "General", 0)] {
            navigation.open(destination)
            pump(host)
            pump(host)
            guard let table = tables(in: host).first,
                  let viewport = pageFrames.frames["page-content"],
                  let section = pageFrames.frames[destination.rawValue] else {
                failures.append("Missing merged destination \(destination.rawValue)")
                continue
            }
            let contentRows = (0..<table.numberOfRows).filter {
                table.rowView(atRow: $0, makeIfNecessary: true)?.isGroupRowStyle == false
            }
            if !viewport.intersects(section) || section.minY < viewport.minY - 1 || section.minY >= viewport.maxY - 40
                || table.selectedRow != contentRows[sidebarIndex] || pageFrames.frames["title:\(title)"] == nil {
                failures.append("Merged destination must be visible and select \(title): \(pageFrames.frames)")
            }
            let titleFrame = pageFrames.frames["title:\(title)"]
            if let scroll = scrollViews(in: host).first(where: { $0.bounds.width > 300 }) {
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
                pump(host)
                let unscrolled = pageFrames.frames[destination.rawValue]
                navigation.open(destination)
                pump(host)
                pump(host)
                let restored = pageFrames.frames[destination.rawValue]
                // Lazy calendar content can refine its height after scrolling; its heading must return to the same position.
                let restoredPosition = restored.map { abs($0.minX - section.minX) < 1 && abs($0.minY - section.minY) < 1 } == true
                if !restoredPosition || pageFrames.frames["title:\(title)"] != titleFrame {
                    failures.append("Repeated \(destination.rawValue) open must restore its scroll position and keep the title fixed: first=\(section), unscrolled=\(String(describing: unscrolled)), restored=\(String(describing: restored)), original title=\(String(describing: titleFrame)), page=\(pageFrames.frames)")
                }
                if destination == .history && unscrolled == restored {
                    failures.append("History repeat-open test must actually scroll away before reopening")
                }
            } else {
                failures.append("Missing body scroll view for repeated \(destination.rawValue) navigation")
            }
            try bitmap(host).representation(using: .png, properties: [:])!
                .write(to: root.appendingPathComponent("merged-\(destination.rawValue).png"))
        }
        print("CHECK merged destinations: content, sidebar selection, titles, direct and repeated scroll")
        plugins.install(UsageFixtureModule.id)
        navigation.pluginID = UsageFixtureModule.id
        navigation.selection = .plugin
        pump(host)
        try bitmap(host).representation(using: .png, properties: [:])!
            .write(to: root.appendingPathComponent("usage-plugin-off.png"))
        if usageFrames.frames["usage"] == nil || plugins.isEnabled(UsageFixtureModule.id) {
            failures.append("Installed disabled usage plugin must show its switch without changing its state")
        }
        plugins.setEnabled(UsageFixtureModule.id, true)
        pump(host)
        if usageFrames.frames["usage"] == nil || !plugins.showUsage {
            failures.append("Enabled usage plugin must retain its switch and display state")
        }
        navigation.selection = .general
        pump(host)
        navigation.selection = .plugin
        pump(host)
        try bitmap(host).representation(using: .png, properties: [:])!
            .write(to: root.appendingPathComponent("usage-plugin-on-reopened.png"))
        plugins.setEnabled(UsageFixtureModule.id, false)
        pump(host)
        if usageFrames.frames["usage"] == nil || !plugins.isInstalled(UsageFixtureModule.id) || plugins.showUsage {
            failures.append("Disabled usage plugin must stay installed and retain its switch")
        }
        let restarted = PluginManagerModel(defaultAdapter: DefaultFeatureAdapter(),
            routingStore: FeatureRoutingStore(url: nil), catalogStore: catalogStore)
        restarted.configureCatalog(sync: sync, presentations: PluginSettingsPresentationRegistry(),
            modules: [UsageFixtureModule.self], allowsExternalIntegrations: false, isolatedPluginIDs: [UsageFixtureModule.id])
        if !restarted.isInstalled(UsageFixtureModule.id) || restarted.isEnabled(UsageFixtureModule.id) {
            failures.append("Usage plugin's disabled state must persist after restart")
        }
        restarted.setEnabled(UsageFixtureModule.id, true)
        if !restarted.showUsage { failures.append("Usage plugin must be re-enabled after restart") }
        let reenabled = PluginManagerModel(defaultAdapter: DefaultFeatureAdapter(),
            routingStore: FeatureRoutingStore(url: nil), catalogStore: catalogStore)
        reenabled.configureCatalog(sync: sync, presentations: PluginSettingsPresentationRegistry(),
            modules: [UsageFixtureModule.self], allowsExternalIntegrations: false, isolatedPluginIDs: [UsageFixtureModule.id])
        if !reenabled.showUsage { failures.append("Usage plugin's enabled state must persist after restart") }
        print("CHECK usage plugin: switch location, off/on, retained installation and restart")
        print("SKIP native click/keyboard integration: this headless process does not become a key app")
        navigation.selection = .appearance
        var baselineFrames: [String: CGRect]?
        for palette in AppearancePalette.allCases {
            appearance.selectPalette(palette)
            pump(host)
            if [.nativeGlass, .softMint, .customTheme].contains(palette) {
                try bitmap(host).representation(using: .png, properties: [:])!
                    .write(to: root.appendingPathComponent("appearance-\(palette.rawValue).png"))
            }
            let frames = appearanceFrames.frames
            guard let theme = frames["theme"], let icons = frames["icons"] else {
                failures.append("\(palette.rawValue): missing appearance section geometry")
                continue
            }
            if let baselineFrames {
                let matches = sameFrame(baselineFrames["theme"]!, theme) && sameFrame(baselineFrames["icons"]!, icons)
                if !matches { failures.append("\(palette.rawValue): appearance section geometry changed from \(baselineFrames) to \(frames)") }
                print("\(matches ? "PASS" : "FAIL") \(palette.rawValue): same theme and icon section geometry")
            } else {
                baselineFrames = frames
                print("PASS \(palette.rawValue): captured theme and icon section geometry")
            }
            if palette != .nativeGlass, let baselineFrames {
                appearance.setColor("#136B52", for: .accent)
                pump(host)
                let editedFrames = appearanceFrames.frames
                let matches = editedFrames["theme"].map { sameFrame(baselineFrames["theme"]!, $0) } == true
                    && editedFrames["icons"].map { sameFrame(baselineFrames["icons"]!, $0) } == true
                if !matches { failures.append("\(palette.rawValue): color edit changed appearance section geometry") }
                print("\(matches ? "PASS" : "FAIL") \(palette.rawValue): color edit preserved section geometry")
            }
        }
        let preview = appearance.image(for: .mint)
        precondition(appearance.image(for: .mint) === preview, "Built-in icon previews must be cached")
        for index in 0..<5 {
            navigation.selection = .general
            pump(host)
            measure("enter-appearance-\(index)") { navigation.selection = .appearance }
        }
        for palette in AppearancePalette.allCases {
            measure("palette-\(palette.rawValue)") { appearance.selectPalette(palette) }
        }
        try bitmap(host).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("settings-appearance.png"))
        appearance.selectPalette(.nativeGlass)
        navigation.selection = .general
        pump(host)
        try bitmap(host).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("settings-general.png"))
        for palette in [AppearancePalette.softMint, .charcoal] {
            appearance.selectPalette(palette)
            pump(host)
            try bitmap(host).representation(using: .png, properties: [:])!
                .write(to: root.appendingPathComponent("general-\(palette.rawValue).png"))
        }
        UserDefaults.standard.setVolatileDomain([AppLanguage.key: "korean"], forName: UserDefaults.argumentDomain)
        window.setContentSize(NSSize(width: 820, height: 620))
        appearance.selectPalette(.nativeGlass)
        navigation.selection = .appearance
        pump(host)
        navigation.selection = .general
        pump(host)
        let koreanTitles = ["언어", "퇴근까지 남은 시간 표시", "메뉴바에 퇴근 예정 시각 표시", "로그인 시 자동 실행"]
        let koreanRows = koreanTitles.compactMap { generalFrames.frames[$0] }
        if pageFrames.frames["title:일반"] == nil { failures.append("Missing Korean General title") }
        let koreanRowsFit = koreanRows.count == koreanTitles.count && abs(host.bounds.width - 820) < 1
            && zip(koreanRows, koreanRows.dropFirst()).allSatisfy { first, second in first.maxY <= second.minY }
            && koreanRows.allSatisfy { $0.minX >= 0 && $0.maxX <= host.bounds.width && $0.maxY <= host.bounds.height }
        if !koreanRowsFit {
            failures.append("Korean general rows are missing, overlap, or do not fit the 820pt host")
        } else {
            print("PASS Korean general settings: four rows at minimum window width")
        }
        if !controlsAlign(koreanTitles + ["현재 버전"], in: generalFrames.frames) {
            failures.append("Korean General and Updates controls do not align or fit")
        }
        try bitmap(host).representation(using: .png, properties: [:])!
            .write(to: root.appendingPathComponent("general-korean.png"))
        navigation.open(.updates)
        pump(host)
        pump(host)
        try bitmap(host).representation(using: .png, properties: [:])!
            .write(to: root.appendingPathComponent("updates-korean.png"))
        navigation.selection = .work
        pump(host)
        if !controlsAlign(["근무", "휴게"], in: generalFrames.frames) {
            failures.append("Korean work/break controls do not align or fit")
        }
        try bitmap(host).representation(using: .png, properties: [:])!
            .write(to: root.appendingPathComponent("work-korean.png"))
        navigation.open(.history)
        pump(host)
        pump(host)
        if pageFrames.frames["title:근무"] == nil || pageFrames.frames["history"] == nil {
            failures.append("Missing Korean Work title or merged history")
        }
        try bitmap(host).representation(using: .png, properties: [:])!
            .write(to: root.appendingPathComponent("history-korean.png"))
        // CLI hosting on this system exposes no SwiftUI AX descendants; preserve the production
        // .isSelected trait and native Button labels, and report that limit instead of inventing AX coverage.
        print("AX descendants exposed by CLI NSHostingView: \(host.accessibilityChildren()?.count ?? 0)")
        print("RESULT palette sidebar structure and isolated selection checks: \(failures.isEmpty ? "passed" : "failed"); built-in icon preview cached")
        let after = try Data(contentsOf: store.url)
        precondition(original == after && !sync.runtimeAllowed)
        print("PASS isolated attendance unchanged, calendar runtime disabled, updater never started, login changes disabled")
        if !failures.isEmpty { print(failures.joined(separator: "\n")); exit(1) }
    }
}
