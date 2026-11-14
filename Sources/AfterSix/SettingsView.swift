import AppPluginCore
import AppPluginHost
import SwiftUI
import ServiceManagement
import AfterSixCore

private typealias SettingsState<Value> = SwiftUI.State<Value>

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, work, history, calendar, plugins, plugin, updates

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: L("일반", "General")
        case .appearance: L("외관", "Appearance")
        case .plugin: L("플러그인 설정", "Plugin settings")
        case .work: L("근무", "Work")
        case .history: L("출근 기록", "Arrival history")
        case .calendar: L("캘린더", "Calendar")
        case .plugins: L("플러그인", "Plugins")
        case .updates: L("업데이트", "Updates")
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintpalette.fill"
        case .plugin: "puzzlepiece.extension"
        case .work: "clock.fill"
        case .history: "calendar"
        case .calendar: "calendar"
        case .plugins: "puzzlepiece.extension"
        case .updates: "arrow.down.circle.fill"
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var selection: SettingsSection? = .general
    @Published var pluginID: String?
    @Published private(set) var requestID = 0

    func open(_ section: SettingsSection) {
        selection = section
        requestID += 1
    }
}

// Fixed fictional examples: formatting follows the selected option without reading attendance or a clock.
enum GeneralSettingsPreview {
    static var guideURL: URL {
        URL(string: L("https://happylulu.cy-choi-lulu.chatgpt.site/guide/",
                      "https://happylulu.cy-choi-lulu.chatgpt.site/en/guide/"))!
    }

    static func countdown(_ display: CountdownDisplay) -> String {
        let value = display.text(seconds: 5_320, korean: L("ko", "en") == "ko")
        return L("\(value) 남음", "\(value) left")
    }

    static func departure(_ display: CountdownDisplay, shown: Bool) -> String {
        let remaining = countdown(display)
        return shown ? L("퇴근 18:00 · \(remaining)", "Leave 18:00 · \(remaining)") : remaining
    }
}

struct SettingsView: View {
    var glass = LuluGlass()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @ObservedObject private var appearance = AppearanceModel.shared
    @ObservedObject var model: AppModel
    @ObservedObject var updater: AppUpdater
    @ObservedObject private var language = AppLanguage.shared
    @ObservedObject var calendarSync: CalendarSyncModel
    @ObservedObject var plugins: PluginManagerModel
    @ObservedObject var featureCalendar: FeatureCalendarModel
    let pluginPresentations: PluginSettingsPresentationRegistry
    @ObservedObject var navigation: SettingsNavigation
    @SettingsState private var showSyncSettings = false
    @FocusState private var sidebarHasFocus: Bool
    private var accent: Color { appearance.accent }
    private var selectedLocale: Locale { _ = language.choice; return displayLocale }
    private var settingsSurface: Color {
        appearance.usesNativeAppearance ? Color(nsColor: .underPageBackgroundColor) : appearance.surface
    }

    var body: some View {
        settingsContent.groupBoxStyle(LuluSettingsGroupBoxStyle(surface: settingsSurface))
    }

    private var settingsContent: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                Text(pageTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, glass.isEnabled ? 24 : 28)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("settings-page-title")
                    .allowsHitTesting(false)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: SettingsLayout.betweenSections) {
                            switch selectedSection {
                            case .general, .updates:
                                generalSection
                                updatesSection
                                    .id(SettingsSection.updates)
                                    .accessibilityIdentifier("settings-updates")
                            case .work, .history:
                                workSection
                                GroupBox(SettingsSection.history.title) { historySection.padding(8) }
                                    .id(SettingsSection.history)
                                    .accessibilityIdentifier("settings-history")
                            case .appearance: AppearanceSettingsView(appearance: appearance)
                            case .calendar:
                                pluginDetail(calendarPluginID)
                            case .plugin:
                                pluginDetail(navigation.pluginID ?? "")
                            case .plugins:
                                PluginSettingsView(model: plugins, presentations: pluginPresentations,
                                    onOpenPlugin: { id in navigation.pluginID = id; navigation.selection = .plugin },
                                    onInstall: installPlugin, onSetEnabled: setPluginEnabled,
                                    needsSetup: { $0 == "leave-detection" && plugins.isEnabled($0) && !model.state.detectHalfDaysFromCalendar })
                            }
                            if let error = model.errorMessage {
                                Label(visibleMessage(error), systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, glass.isEnabled ? 24 : 28)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                    .accessibilityIdentifier("settings-page-content")
                    .task(id: navigation.requestID) {
                        // Wait until the merged page has laid out its destination, including on repeated opens.
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        if selectedSection == .history || selectedSection == .updates {
                            proxy.scrollTo(selectedSection, anchor: .top)
                        }
                    }
                }
                .id("\(selectedSection.rawValue)|\(navigation.pluginID ?? "")")
            }
            .ignoresSafeArea(.container, edges: .top)
            .background(appearance.usesNativeAppearance ? Color.clear : appearance.background)
        }
        .frame(minWidth: 820, minHeight: 620)
        .onAppear { model.refresh() }
        .foregroundStyle(appearance.text)
        .background {
            if appearance.usesNativeAppearance {
                (colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color.white)
                    .ignoresSafeArea()
            } else {
                appearance.background
            }
        }
        .overlay {
            if glass.isEnabled {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.20), lineWidth: 1)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .luluWindowColorScheme(appearance.preferredColorScheme)
        .luluGlassControls(usesSystemAppearance: true)
        .tint(accent)
        .environment(\.locale, selectedLocale)
    }

    private var selectedSection: SettingsSection { navigation.selection ?? .general }

    private var pageSection: SettingsSection {
        switch selectedSection {
        case .history: .work
        case .updates: .general
        default: selectedSection
        }
    }

    private var pageTitle: String {
        switch pageSection {
        case .plugin: plugins.catalog.first { $0.id == navigation.pluginID }?.name ?? pageSection.title
        case .calendar: plugins.catalog.first { $0.id == calendarPluginID }?.name ?? pageSection.title
        case .plugins: L("플러그인 관리", "Manage plugins")
        default: pageSection.title
        }
    }

    private enum SidebarSelection: Hashable {
        case section(SettingsSection)
        case plugin(String)
    }

    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(get: {
            switch selectedSection {
            case .plugin:
                navigation.pluginID.map(SidebarSelection.plugin)
            case .calendar:
                .plugin(calendarPluginID)
            default:
                .section(pageSection)
            }
        }, set: { selection in
            guard let selection else { return }
            switch selection {
            case .section(let section):
                navigation.selection = section
            case .plugin(let id):
                navigation.pluginID = id
                navigation.selection = .plugin
            }
        })
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(selection: sidebarSelection) {
                Section(L("기본 설정", "Core settings")) {
                    ForEach([SettingsSection.general, .appearance, .work]) { section in
                        sidebarLabel(section.title, symbol: section.symbol,
                                     selected: sidebarSelection.wrappedValue == .section(section))
                            .tag(SidebarSelection.section(section))
                    }
                    sidebarLabel(L("플러그인 관리", "Manage plugins"), symbol: "puzzlepiece.extension.fill",
                                 selected: sidebarSelection.wrappedValue == .section(.plugins))
                        .tag(SidebarSelection.section(.plugins))
                }
                Section(L("설치된 플러그인", "Installed plugins")) {
                    ForEach(plugins.installed) { entry in
                        sidebarLabel(entry.name, symbol: entry.id == "cpu-runner" ? "desktopcomputer" : entry.symbol,
                                     selected: sidebarSelection.wrappedValue == .plugin(entry.id))
                            .tag(SidebarSelection.plugin(entry.id))
                    }
                    if plugins.installed.isEmpty {
                        Text(L("설치된 항목이 없어요", "No plugins installed"))
                            .font(.caption).foregroundStyle(.secondary)
                            .disabled(true)
                    }
                }
            }
            .listStyle(.sidebar)
            .focused($sidebarHasFocus)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .accessibilityLabel(L("설정 항목", "Settings sections"))
            Link(destination: GeneralSettingsPreview.guideURL) {
                sidebarLabel(L("사용 안내", "User guide"), symbol: "book")
            }
            .accessibilityIdentifier("settings-user-guide")
            .padding(12)
        }
        .frame(width: 230).frame(maxHeight: .infinity)
        .background {
            (appearance.usesNativeAppearance
                ? (colorScheme == .dark ? Color(nsColor: .underPageBackgroundColor) : Color(white: 0.92))
                : appearance.sidebar).ignoresSafeArea(edges: [.top, .bottom])
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1).allowsHitTesting(false)
        }
    }

    private func sidebarLabel(_ title: String, symbol: String, selected: Bool = false) -> some View {
        let highlighted = selected && controlActiveState == .key && sidebarHasFocus
        return Label {
            Text(title).foregroundStyle(highlighted ? Color.white : (selected ? Color.primary : appearance.text))
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .imageScale(.medium)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(highlighted ? Color.white : Color.blue)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        }
    }

    private func installPlugin(_ id: String) {
        plugins.install(id)
        if id == "leave-detection", plugins.isEnabled(id) { model.setCalendarHalfDayDetection(true) }
    }

    private func setPluginEnabled(_ id: String, _ enabled: Bool) {
        plugins.setEnabled(id, enabled)
        if id == "leave-detection", plugins.isEnabled(id) == enabled { model.setCalendarHalfDayDetection(enabled) }
    }

    private var calendarPluginID: String {
        let id = plugins.router.selectedID(for: .calendar)
        return plugins.catalog.contains(where: { $0.id == id }) ? id : "mac-calendar"
    }

    @ViewBuilder private func pluginDetail(_ id: String) -> some View {
        if let entry = plugins.catalog.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("개발자 · \(entry.author)", "Developer · \(entry.author)"))
                Text(entry.summary).foregroundStyle(.secondary)
            }.font(SettingsLayout.detailFont).foregroundStyle(.secondary)
            if plugins.isInstalled(id) {
              settingsGroup(L("사용 설정", "Usage")) {
                settingRow(id == "ai-usage" ? L("사용량 보기", "Show usage") : L("플러그인 사용", "Use plugin")) {
                Toggle(id == "ai-usage" ? L("사용량 보기", "Show usage") : L("플러그인 사용", "Use plugin"), isOn: Binding(
                    get: { plugins.isEnabled(id) }, set: { setPluginEnabled(id, $0) }))
                    .toggleStyle(.switch).labelsHidden()
                    .accessibilityLabel(id == "ai-usage" ? L("사용량 보기", "Show usage") : L("플러그인 사용", "Use plugin"))
                    .disabled(!plugins.canChangeCatalog || (id == "ai-usage" && !plugins.allowsExecution(id)))
                    .accessibilityIdentifier(id == "ai-usage" ? "settings-usage-switch" : "settings-plugin-switch-\(id)")
                }
              }
                if plugins.isEnabled(id) {
                    if id == "mac-calendar" {
                        Picker(L("캘린더 화면", "Calendar view"), selection: $showSyncSettings) {
                            Text(L("일정", "Events")).tag(false)
                            Text(L("동기화 설정", "Sync settings")).tag(true)
                        }.pickerStyle(.segmented)
                        if showSyncSettings {
                            CalendarSyncSettingsView(model: calendarSync)
                                .onAppear { calendarSync.prepareForDisplay() }
                        } else {
                            FeatureCalendarView(model: featureCalendar, plugins: plugins, sync: calendarSync,
                                onOpenSettings: { navigation.selection = .plugins })
                        }
                        FeatureSourceSettingsView(model: plugins, features: [.calendar])
                    } else if id == "leave-detection" {
                        calendarSection
                        FeatureSourceSettingsView(model: plugins, features: [.halfDay])
                    } else {
                        if let settings = pluginPresentations.view(for: id) { settings }
                        else { Text(L("이 플러그인은 별도 설정이 없습니다.", "This plugin has no additional settings.")) }
                        let supported = plugins.registrations.first(where: { $0.id == id })?.adapter.descriptor.features ?? []
                        let routedFeatures = [AppFeature.calendar, .leave].filter { supported.contains($0) }
                        if !routedFeatures.isEmpty {
                            FeatureSourceSettingsView(model: plugins, features: routedFeatures)
                        }
                    }
                } else {
                    Text(L("사용 안 함 · 연결 설정과 기록은 보존됩니다.", "Off · connection settings and records are preserved."))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(L("설치", "Install")) { installPlugin(id) }
                    .disabled(!entry.available || !plugins.canChangeCatalog)
            }
            if let message = plugins.message {
                Label(visibleMessage(message), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
        } else {
            Text(L("플러그인 관리에서 기능을 추가해 주세요.", "Add a feature in plugin management."))
            Button(L("플러그인 관리", "Manage plugins")) { navigation.selection = .plugins }
        }
    }

    private var generalSection: some View {
        settingsGroup(L("사용 환경", "Preferences")) {
          VStack(spacing: 0) {
            settingRow(L("언어", "Language")) {
                Picker(L("언어", "Language"), selection: Binding(
                    get: { language.choice }, set: { language.select($0) })) {
                    ForEach(LanguageChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }.pickerStyle(.menu).labelsHidden()
                    .accessibilityLabel(L("언어", "Language"))
                    .fixedSize(horizontal: true, vertical: false)
            }
            generalDivider
            settingRow(L("퇴근까지 남은 시간 표시", "Countdown display")) {
                settingExample(GeneralSettingsPreview.countdown(model.countdownDisplay))
                DisclosureGroup(L("표시 방식 안내", "About display formats")) {
                    Text(L("시간은 0.1시간씩, 다른 단위는 올림합니다. 밀리초는 0.1초마다 갱신합니다.",
                           "Hours round up in 0.1-hour steps; other units round up. Milliseconds refresh every 0.1 seconds."))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } control: {
                Picker(L("퇴근까지 남은 시간 표시", "Countdown display"), selection: Binding(
                    get: { model.countdownDisplay }, set: { model.setCountdownDisplay($0) })) {
                    ForEach(CountdownDisplay.allCases, id: \.self) { choice in
                        Text(choice.displayLabel).tag(choice)
                    }
                }.pickerStyle(.menu).labelsHidden()
                    .accessibilityLabel(L("퇴근까지 남은 시간 표시", "Countdown display"))
                    .fixedSize(horizontal: true, vertical: false)
            }
            generalDivider
            settingRow(L("메뉴바에 퇴근 예정 시각 표시", "Show expected departure in menu bar")) {
                settingExample(GeneralSettingsPreview.departure(model.countdownDisplay, shown: model.showDepartureInMenuBar))
            } control: {
                Toggle(L("메뉴바에 퇴근 예정 시각 표시", "Show expected departure in menu bar"), isOn: Binding(
                    get: { model.showDepartureInMenuBar }, set: { model.setShowDepartureInMenuBar($0) }))
                    .toggleStyle(.switch).labelsHidden()
                    .accessibilityLabel(L("메뉴바에 퇴근 예정 시각 표시", "Show expected departure in menu bar"))
                    .accessibilityIdentifier("settings-departure-switch")
            }
            generalDivider
            settingRow(L("로그인 시 자동 실행", "Launch at login")) {
                Text(model.loginDescription)
                if model.loginStatus == .requiresApproval {
                    Button(L("시스템 설정에서 허용", "Allow in System Settings")) { SMAppService.openSystemSettingsLoginItems() }
                }
            } control: {
                Toggle(L("로그인 시 자동 실행", "Launch at login"), isOn: Binding(
                    get: { model.loginEnabled }, set: { model.setLoginEnabled($0) }))
                    .toggleStyle(.switch).labelsHidden().disabled(!model.allowsLoginItemChanges)
                    .accessibilityLabel(L("로그인 시 자동 실행", "Launch at login"))
                    .accessibilityIdentifier("settings-login-switch")
            }
          }
        }
    }

    private var generalDivider: some View {
        Divider().padding(.horizontal, SettingsLayout.rowHorizontal).accessibilityHidden(true)
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox(title) { content() }
            .groupBoxStyle(LuluSettingsGroupBoxStyle(surface: settingsSurface, contentPadding: 0))
    }

    private func settingRow<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        settingRow(title, detail: { EmptyView() }, control: control)
    }

    private func settingRow<Detail: View, Control: View>(
        _ title: String, @ViewBuilder detail: () -> Detail, @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(SettingsLayout.bodyFont)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) { detail() }
                    .font(SettingsLayout.detailFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            control()
        }
        .font(SettingsLayout.bodyFont)
        .padding(.horizontal, SettingsLayout.rowHorizontal).padding(.vertical, SettingsLayout.rowVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingExample(_ value: String) -> some View {
        Text(L("예시: \(value)", "Example: \(value)"))
            .font(.system(size: 11).monospacedDigit())
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(L("표시 예시", "Display example"))
            .accessibilityValue(value)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            AttendanceCalendarView(model: model, settingsPresentation: true, settingsAccent: accent)
            HStack {
                Spacer()
                Button(L("기록 폴더 열기", "Open records folder")) { model.showData() }
            }
        }
    }

    private var workSection: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.betweenSections) {
            settingsGroup(L("오늘 근무", "Today's work")) {
                VStack(alignment: .leading, spacing: 12) {
                    TodayDayTypeView(model: model)
                    AttendanceControlsView(model: model)
                }
                .font(SettingsLayout.bodyFont)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SettingsLayout.rowHorizontal)
            }
            VStack(alignment: .leading, spacing: SettingsLayout.titleToCard) {
              settingsGroup(L("근무 시간", "Work schedule")) {
                VStack(spacing: 0) {
                    settingRow(L("근무", "Work")) {
                        HStack(spacing: 8) {
                            Text(model.duration(model.state.settings.workMinutes)).monospacedDigit().accessibilityHidden(true)
                            Stepper(L("근무 시간", "Work duration"), value: Binding(
                                get: { model.state.settings.workMinutes },
                                set: { model.updateSettings(work: $0, rest: model.state.settings.breakMinutes) }
                            ), in: 60...960, step: 30)
                                .labelsHidden()
                                .accessibilityLabel(L("근무 시간", "Work duration"))
                                .accessibilityValue(model.duration(model.state.settings.workMinutes))
                        }.fixedSize()
                    }
                    generalDivider
                    settingRow(L("휴게", "Break")) {
                        HStack(spacing: 8) {
                            Text(model.duration(model.state.settings.breakMinutes)).monospacedDigit().accessibilityHidden(true)
                            Stepper(L("휴게 시간", "Break duration"), value: Binding(
                                get: { model.state.settings.breakMinutes },
                                set: { model.updateSettings(work: model.state.settings.workMinutes, rest: $0) }
                            ), in: 0...240, step: 15)
                                .labelsHidden()
                                .accessibilityLabel(L("휴게 시간", "Break duration"))
                                .accessibilityValue(model.duration(model.state.settings.breakMinutes))
                        }.fixedSize()
                    }
                }
              }
              VStack(alignment: .leading, spacing: 4) {
                Text(L("오늘 퇴근 예정에도 바로 반영됩니다. 잠금·절전 중에도 시간이 흘러갑니다.", "Changes affect today’s departure immediately. Time continues while the Mac is locked or asleep."))
                DisclosureGroup(L("단축 근무와 반차 안내", "About shorter days and half-days")) {
                    Text(L("매달 마지막 금요일에는 퇴근 예정이 2시간 빨라집니다. 반차는 휴게 없이 출근 4시간 뒤 퇴근하며, 마지막 금요일 단축과 중복 적용하지 않아요.", "On the last Friday of each month, departure is 2 hours earlier. A half-day ends 4 hours after arrival with no break or additional Friday reduction."))
                        .fixedSize(horizontal: false, vertical: true)
                }
              }
              .font(SettingsLayout.detailFont).foregroundStyle(.secondary)
              .padding(.horizontal, SettingsLayout.rowHorizontal)
            }
        }
    }

    private var calendarSection: some View {
        GroupBox(L("캘린더", "Calendar")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(plugins.router.selectedID(for: .halfDay) == "mac-calendar"
                     ? L("접근 가능한 Mac 캘린더의 '오전 반차'·'오후 반차' 제목을 읽습니다. 공유 캘린더의 다른 사람 반차도 확인해 주세요. 일정이 모호하면 출근 시각으로 판단해요.", "Reads morning and afternoon off titles from accessible Mac calendars. Check shared calendars for other people’s leave. Ambiguous events fall back to arrival time.")
                     : L("\(plugins.adapterName(plugins.router.selectedID(for: .halfDay))) 일정의 '오전 반차'·'오후 반차' 제목을 읽습니다. 일반 연차에서 반차 유형을 추정하지 않으며, 직접 지정한 근무 유형은 유지합니다.", "Reads explicit morning/afternoon off titles from \(plugins.adapterName(plugins.router.selectedID(for: .halfDay))). Leave amounts do not imply a half-day type. Manual workday choices are preserved."))
                    .foregroundStyle(.secondary)
                if !model.state.detectHalfDaysFromCalendar {
                    Label(L("설정 필요 · 일정 연결과 읽기 권한을 확인한 뒤 자동 인식을 시작하세요.", "Setup required · choose a source and grant read access, then start detection."), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button(L("자동 인식 시작", "Start automatic detection")) { model.setCalendarHalfDayDetection(true) }
                }
                Button(L("연결·권한 다시 확인", "Check source and permissions")) { model.setCalendarHalfDayDetection(true) }
                if model.state.detectHalfDaysFromCalendar {
                    Button(L("반차 일정 새로고침", "Refresh half-day events")) { model.checkCalendarHalfDayNow() }
                }
                if let message = model.calendarHalfDayMessage {
                    Text(visibleMessage(message)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.titleToCard) {
          settingsGroup(L("업데이트", "Updates")) {
            VStack(spacing: 0) {
                settingRow(L("현재 버전", "Current version")) {
                    Text(updater.version).foregroundStyle(.secondary)
                }
                generalDivider
                HStack {
                    Spacer()
                    Button(L("지금 업데이트 확인", "Check for updates now")) { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
                .padding(.horizontal, SettingsLayout.rowHorizontal).padding(.vertical, SettingsLayout.rowVertical)
            }
          }
          VStack(alignment: .leading, spacing: 4) {
            Text(L("업데이트는 출근 기록과 설정을 유지합니다.", "Updates preserve your records and settings."))
            DisclosureGroup(L("업데이트 동작 안내", "About updates")) {
              VStack(alignment: .leading, spacing: 4) {
                Text(L("서명된 새 버전을 앱에서 받아 설치합니다. 출근 기록과 설정은 유지됩니다.", "Downloads and installs signed updates in the app, preserving your records and settings."))
                Text(L("기존 자동 확인·설치 설정은 유지됩니다. 자동 설치를 사용 중이면 창을 닫고 출근 처리·캘린더 동기화가 끝난 뒤 앱이 재시작됩니다. 설치 준비가 끝나면 재시작까지 설정을 잠시 바꿀 수 없습니다.", "Your existing automatic update preferences are retained. If automatic installation is enabled, the app restarts after its windows are closed and attendance/calendar work has finished. Settings are locked from installation preparation until restart."))
              }.fixedSize(horizontal: false, vertical: true)
            }
            if let error = updater.startupError {
                Text(visibleMessage(error)).foregroundStyle(.orange)
            }
          }
          .font(SettingsLayout.detailFont).foregroundStyle(.secondary)
          .padding(.horizontal, SettingsLayout.rowHorizontal)
        }
    }
}

private struct LuluSettingsGroupBoxStyle: GroupBoxStyle {
    let surface: Color
    var contentPadding: CGFloat = 6
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: SettingsLayout.titleToCard) {
            configuration.label
                .font(SettingsLayout.sectionFont)
                .padding(.horizontal, SettingsLayout.rowHorizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            configuration.content
                .padding(contentPadding).frame(maxWidth: .infinity, alignment: .leading)
                .background(surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
