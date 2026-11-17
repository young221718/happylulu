import SwiftUI
import AIUsagePlugin

public struct AIUsageSettingsView: View {
    @ObservedObject private var model: AIUsageModel
    public init(model: AIUsageModel) { self.model = model }
    private func t(_ ko: String, _ en: String) -> String { model.text(ko, en) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            profileSettings
            GroupBox(model.providerName + t(" 사용량", " usage")) {
                VStack(alignment: .leading, spacing: 12) {
                    row(t("주간 잔여량", "Weekly remaining"), value: model.snapshot.map { "\($0.weekly.remainingPercent)%" } ?? "—")
                    HStack {
                        Text(t("초기화", "Resets")); Spacer()
                        if let reset = model.snapshot?.weekly.resetDate {
                            Text(reset, format: .dateTime.month().day().hour().minute()).monospacedDigit()
                        } else { Text("—") }
                    }
                    row(t("시간당 소모율", "Hourly consumption"), value: model.analysis.hour.map {
                        String(format: "%.3f", $0.perHour) + t(" %p/시간", " pp/hour")
                    } ?? "—")
                    if let rate = model.analysis.hour {
                        Text(t("최근 \(Int(rate.observedMinutes))분 관측 기준", "Based on the last \(Int(rate.observedMinutes)) observed minutes"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let snapshot = model.snapshot {
                        HStack {
                            Text(t("마지막 조회", "Last updated")); Spacer()
                            Text(snapshot.fetchedAt, format: .dateTime.hour().minute()).monospacedDigit()
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    if model.isStale, model.snapshot != nil {
                        Text(t("이전 조회 값입니다.", "Showing the previous reading.")).font(.caption).foregroundStyle(.secondary)
                    }
                    if let message = model.message {
                        Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button(t("지금 새로고침", "Refresh now")) { model.refreshData() }
                            .disabled(model.isRunning || !model.canRequestUsage)
                        if model.isRefreshing { ProgressView().controlSize(.small).accessibilityLabel(t("사용량 조회 중", "Reading usage")) }
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox(t("표시 및 갱신", "Display and refresh")) {
                VStack(alignment: .leading, spacing: 12) {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                        GridRow {
                            Text(t("메뉴바 표시", "Menu bar label"))
                            menuBarPreview
                            Picker(t("메뉴바 표시", "Menu bar label"), selection: Binding(
                                get: { model.preferences.labelFormat }, set: { value in model.updatePreferences { $0.labelFormat = value } })) {
                                Text(model.providerName + " + %").tag(LabelFormat.named)
                                Text(t("아이콘 + %", "Icon + %")).tag(LabelFormat.icon)
                                Text(t("%만", "% only")).tag(LabelFormat.percentage)
                            }.labelsHidden().frame(width: 160)
                        }
                        GridRow {
                            Text(t("갱신 주기", "Refresh interval"))
                            Text(t("\(model.preferences.refreshMinutes)분", "\(model.preferences.refreshMinutes) min"))
                                .foregroundStyle(.secondary)
                            Picker(t("갱신 주기", "Refresh interval"), selection: Binding(
                                get: { model.preferences.refreshMinutes }, set: { value in model.updatePreferences { $0.refreshMinutes = value } })) {
                                ForEach([1, 5, 10, 15, 30], id: \.self) { minutes in Text(t("\(minutes)분", "\(minutes) min")).tag(minutes) }
                            }.labelsHidden().frame(width: 160)
                        }
                        GridRow {
                            Text(t("잔여량 부족 알림", "Low allowance notification"))
                            Text(model.preferences.notificationsEnabled ? t("켬", "On") : t("끔", "Off"))
                                .foregroundStyle(.secondary)
                            Toggle(t("잔여량 부족 알림", "Low allowance notification"), isOn: Binding(
                                get: { model.preferences.notificationsEnabled }, set: { model.setNotifications($0) }))
                                .labelsHidden().toggleStyle(.switch)
                                .disabled(!model.supportsNotifications)
                        }
                        if model.preferences.notificationsEnabled {
                            GridRow {
                                Text(t("알림 기준", "Notify below"))
                                Text("\(model.preferences.notificationThreshold)%").foregroundStyle(.secondary)
                                Picker(t("알림 기준", "Notify below"), selection: Binding(
                                    get: { model.preferences.notificationThreshold }, set: { value in model.updatePreferences { $0.notificationThreshold = value } })) {
                                    ForEach([10, 20, 30], id: \.self) { value in Text("\(value)%").tag(value) }
                                }.labelsHidden().frame(width: 160)
                            }
                        }
                    }
                    if model.preferences.labelFormat == .icon, model.menuBarPreview.iconPNG == nil {
                        Text(t("이 연결에는 사용할 아이콘이 없어 공급자 이름으로 표시합니다.",
                               "No icon is available for this connection; showing the provider name."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            if model.usesCodexConnection {
              GroupBox(t("Codex 연결", "Codex connection")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.executablePath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if !model.preferences.configDirectory.isEmpty {
                        Text(t("계정 폴더: ", "Account folder: ") + model.preferences.configDirectory)
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button(t("실행 파일 선택", "Choose executable")) { model.chooseExecutable() }
                        if !model.preferences.cliPath.isEmpty {
                            Button(t("자동 찾기", "Find automatically")) { model.updatePreferences { $0.cliPath = "" } }
                        }
                    }.disabled(model.isLoggingIn || model.settingsReadOnly)
                    if model.selectedProfile != nil {
                        Button(t("전용 계정 폴더 선택", "Choose dedicated account folder")) { model.chooseProfileFile() }
                            .disabled(model.settingsReadOnly)
                        Text(t("새 Codex 프로필은 계정 폴더를 직접 선택해야 조회합니다. 이 폴더의 CLI 로그인만 사용합니다.",
                               "New Codex profiles require an explicitly selected account folder and use only that folder's sign-in."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if model.isLoggingIn {
                        Button(t("로그인 취소", "Cancel sign-in")) { model.cancelLogin() }
                    } else {
                        Button(model.snapshot == nil ? t("ChatGPT로 로그인", "Sign in with ChatGPT") : t("다른 계정으로 로그인", "Sign in with another account")) { model.login() }
                            .disabled(model.isRunning || !model.canRequestUsage)
                    }
                    Text(t("기존 Codex 로그인을 사용합니다. 다른 계정으로 로그인하면 Codex CLI 계정도 변경됩니다.",
                           "Uses your existing Codex sign-in. Signing in with another account also changes the Codex CLI account."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(8)
              }
            } else {
                GroupBox(t("statusLine 연결", "statusLine connection")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(model.selectedProfile?.reportPath.isEmpty == false ? model.selectedProfile!.reportPath : t("선택한 사용량 파일 없음", "No usage file selected"))
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack {
                            Button(t("내보내기 도우미 저장", "Save export helper")) { model.saveStatusLineHelper() }
                            Button(t("사용량 파일 선택", "Choose usage file")) { model.chooseProfileFile() }
                        }.disabled(model.settingsReadOnly)
                        Text(t("도우미를 기존 statusLine에 직접 연결하세요. 앱은 로그인이나 CLI 설정 변경 없이 파일만 읽습니다. CLI가 새 데이터를 내보낼 때 갱신되며 15분이 지난 파일은 사용하지 않습니다.",
                               "Connect the helper to your existing statusLine explicitly. The app only reads the file. Readings update when the CLI exports new data; files older than 15 minutes are rejected."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if model.selectedProfile?.providerID == "claude" {
                            Text(t("Claude는 계정 식별자를 제공하지 않아 소모율 이력과 알림을 사용하지 않습니다.",
                                   "Claude provides no account identity; consumption history and notifications are unavailable."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Link(t("연결 안내", "Connection guide"), destination: URL(string: "https://github.com/young221718/happylulu/blob/mac/dev/docs/AI-MODEL-USAGE.md")!)
                    }.padding(8)
                }
            }
        }
    }
    private var profileSettings: some View {
        GroupBox(t("사용량 연결", "Usage connections")) {
            VStack(alignment: .leading, spacing: 12) {
                Picker(t("연결 프로필", "Connection profile"), selection: Binding(
                    get: { model.profileSettings.selectedID ?? "" }, set: { model.selectProfile($0.isEmpty ? nil : $0) })) {
                    Text(t("기존 공개 Codex 연결", "Existing released Codex connection")).tag("")
                    ForEach(model.profileSettings.profiles) { profile in
                        Text(profile.name + " · " + (model.providerRegistry.descriptor(for: profile.providerID)?.name ?? profile.providerID)).tag(profile.id)
                    }
                }
                HStack {
                    Menu(t("연결 추가", "Add connection")) {
                        ForEach(model.providerRegistry.providers) { provider in
                            Button(provider.name) { model.addProfile(providerID: provider.id) }
                        }
                    }
                    if let profile = model.selectedProfile {
                        TextField(t("연결 이름", "Connection name"), text: Binding(
                            get: { model.selectedProfile?.name ?? profile.name },
                            set: { value in model.updateSelectedProfile { $0.name = value } }))
                        Button(t("연결 제거", "Remove connection")) { model.removeSelectedProfile() }
                    }
                }
                Text(t("기존 공개 Codex와 개발판 연결은 보존하며, 새 연결의 설정·관측 이력·알림은 각각 분리합니다.",
                       "Released Codex and previous development connections are preserved. Each new connection has separate settings, observations, and notifications."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(8)
        }.disabled(model.settingsReadOnly)
    }
    private var menuBarPreview: some View {
        let item = model.menuBarPreview
        return HStack(spacing: 4) {
            if let data = item.iconPNG, let image = NSImage(data: data) {
                Image(nsImage: image).renderingMode(item.iconIsTemplate ? .template : .original)
                    .resizable().scaledToFit()
                    .frame(width: item.iconIsTemplate ? 16 : 14, height: item.iconIsTemplate ? 16 : 14)
                    .accessibilityHidden(true)
            }
            Text(item.title).monospacedDigit()
        }
        .frame(minWidth: 90, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.accessibilityLabel)
    }
    private func row(_ title: String, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).monospacedDigit() }
    }
}
