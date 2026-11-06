import SwiftUI
import AIUsagePlugin

public struct AIUsageSettingsView: View {
    @ObservedObject private var model: AIUsageModel
    @State private var configDirectoryDraft = ""
    public init(model: AIUsageModel) { self.model = model }
    private func t(_ ko: String, _ en: String) -> String { model.text(ko, en) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(t("계정", "Accounts")) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(t("연결", "Connection"), selection: Binding(
                        get: { model.preferences.selectedProfileID }, set: { model.selectProfile($0) })) {
                        ForEach(model.preferences.profiles) { profile in
                            Text(profile.name + " · " + profile.provider.name).tag(profile.id)
                        }
                    }
                    TextField(t("이름", "Name"), text: Binding(
                        get: { model.selectedProfile.name }, set: { value in model.updateSelectedProfile { $0.name = value } }))
                    HStack {
                        Menu(t("계정 추가", "Add account")) {
                            ForEach(UsageProviderKind.allCases, id: \.self) { provider in
                                Button(provider.name) { model.addProfile(provider: provider) }
                            }
                        }
                        Button(t("목록에서 제거", "Remove from list")) { model.removeSelectedProfile() }
                            .disabled(model.preferences.profiles.count < 2)
                    }
                    Text(t("선택한 연결만 갱신합니다. 목록에서 제거해도 CLI 로그인 파일은 삭제하지 않습니다.",
                           "Only the selected connection refreshes. Removing it from this list does not delete CLI sign-in files."))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
            GroupBox(t("\(model.providerName) 사용량", "\(model.providerName) usage")) {
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
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        row(model.tokenSpeedDisplayTitle, value: model.currentTokenSpeedSample.map {
                            String(format: "%.1f tok/s", $0.tokensPerSecond)
                        } ?? "—")
                    }
                    if let snapshot = model.snapshot {
                        HStack {
                            Text(model.selectedProfile.provider == .antigravity ? t("사용량 기준 시각", "Usage as of") : t("마지막 조회", "Last updated")); Spacer()
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
                            .disabled(model.isRunning)
                        if model.isRefreshing { ProgressView().controlSize(.small).accessibilityLabel(t("사용량 조회 중", "Reading usage")) }
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox(t("토큰 속도 측정", "Token speed measurement")) {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.selectedProfile.provider == .codex {
                            Picker(t("측정 출처", "Measurement source"), selection: Binding(
                                get: { model.tokenMeasurementSource }, set: { model.setTokenMeasurementSource($0) })) {
                                Text(t("최근 30일 생성 세션 자동 관측", "Automatically observe sessions created in the last 30 days")).tag(TokenMeasurementSource.codexRecentSessions)
                                Text(t("선택한 로컬 세션 파일", "Selected local session file")).tag(TokenMeasurementSource.codexSessionFile)
                                Text(t("새 CLI 세션의 trace", "Trace from a new CLI session")).tag(TokenMeasurementSource.newSession)
                            }
                            if model.tokenMeasurementSource == .codexSessionFile {
                                Button(t("Codex 세션 JSONL 선택", "Choose Codex session JSONL")) { model.chooseCodexSessionFile() }
                                if !model.codexSessionFilePath.isEmpty {
                                    Text(model.codexSessionFilePath).font(.caption).textSelection(.enabled)
                                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        Text(tokenMeasurementExplanation)
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            if model.tokenTelemetryConnection != nil || model.isTokenMeasurementStarting || model.isObservingCodexSession {
                                Button(t("측정 중지", "Stop measurement")) { model.stopTokenMeasurement() }
                            } else {
                                Button(t("로컬 측정 시작", "Start local measurement")) { model.startTokenMeasurement() }
                                    .disabled(!model.canStartTokenMeasurement)
                            }
                            if model.isTokenMeasurementStarting { ProgressView().controlSize(.small) }
                        }
                        if let sample = model.currentTokenSpeedSample {
                            Text(t("출력 \(sample.outputTokens)토큰 · 측정 구간 \(String(format: "%.2f", sample.durationMilliseconds / 1000))초", "\(sample.outputTokens) output tokens · \(String(format: "%.2f", sample.durationMilliseconds / 1000))s measured interval"))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(sample.recordedAt, format: .dateTime.hour().minute().second()).font(.caption).foregroundStyle(.secondary)
                        } else if model.isObservingCodexSession {
                            Text(model.tokenMeasurementSource == .codexRecentSessions ?
                                 (model.isCatchingUpCodexSessions ? t("최근 세션 기록을 읽는 중입니다.", "Reading recent session records.") :
                                    t("최근 세션 \(model.recentCodexSessionCount)개를 관측 중입니다. 최근 15분 안에 기록된 출력 토큰 수와 시간이 필요합니다. 30일 이전에 생성한 세션은 파일을 선택해 주세요.", "Observing \(model.recentCodexSessionCount) recent sessions. Output tokens and timing recorded within the last 15 minutes are required. Select the file for a session created over 30 days ago.")) :
                                 t("선택한 파일에서 토큰 수와 시간이 있는 최근 기록을 기다리는 중입니다.", "Waiting for a recent record with token and timing fields in the selected file."))
                                .font(.caption).foregroundStyle(.secondary)
                        } else if model.tokenTelemetryConnection != nil {
                            Text(t("아래 명령으로 시작한 세션의 새 측정값을 기다리는 중입니다.", "Waiting for a new measurement from a session started with the command below."))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(model.selectedProfile.provider == .codex && model.tokenMeasurementSource == .codexSessionFile ?
                                t("관측할 JSONL 파일을 선택한 뒤 측정을 시작하세요.", "Choose a JSONL file to observe, then start measurement.") : model.selectedProfile.provider == .codex && model.tokenMeasurementSource == .codexRecentSessions ?
                                t("측정을 시작하면 최근 로컬 세션을 다시 자동 관측합니다.", "Start measurement to resume automatic observation of recent local sessions.") :
                                t("측정을 시작하면 새 세션에 사용할 실행 명령을 표시합니다.", "Start measurement to show a launch command for a new session."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if model.tokenMeasurementSource == .codexRecentSessions, model.unsupportedCodexSessionCount > 0 {
                            Text(t("\(model.unsupportedCodexSessionCount)개 세션은 측정할 수 없습니다. 지원하는 토큰·시간 기록이 필요합니다.", "\(model.unsupportedCodexSessionCount) sessions could not be measured. Supported token and timing records are required."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let command = model.tokenTelemetryCommand {
                            Text(tokenLaunchExplanation)
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if model.selectedProfile.provider != .antigravity {
                                Text(t("회사 관리 정책이나 otelHeadersHelper가 적용되면 이 연결의 전송 경로·헤더가 바뀌거나 연결이 거절될 수 있습니다. 조직의 수집 정책을 유지해야 하는 환경에서는 사용하지 마세요.",
                                   "Managed policies or otelHeadersHelper can override this connection's destination or headers, or prevent it from connecting. Do not use this when your environment must retain organizational collection settings."))
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Text(command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(t("실행 명령 복사", "Copy launch command")) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(command, forType: .string)
                            }
                            Text(t("명령에는 이번 연결의 임시 키가 포함됩니다. 클립보드·터미널 이력에 남거나 실행 중 프로세스 인자·환경에서 보일 수 있습니다. 측정을 중지하거나 연결을 바꾸면 키가 만료됩니다. 토큰 측정을 위해 요청·응답 원문을 저장하지 않습니다.",
                                   "The command includes this connection's temporary key. It can remain in the clipboard or shell history and be visible in process arguments or environment while running. Stopping or switching connections expires it. Request and response text is not stored for token measurement."))
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        if let message = model.tokenTelemetryMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                    }.padding(8)
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
                                .disabled(model.selectedProfile.provider == .antigravity)
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
                        Text(t("이 제공자의 심볼을 표시할 수 없어 이름으로 표시합니다.",
                               "The provider symbol is unavailable; showing its name."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox(t("\(model.providerName) 연결", "\(model.providerName) connection")) {
                VStack(alignment: .leading, spacing: 12) {
                    if model.selectedProfile.provider == .codex || (model.selectedProfile.provider == .antigravity && model.selectedProfile.allowAntigravityCLI) {
                        Text(model.executablePath).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(t("실행 파일 선택", "Choose executable")) { model.chooseExecutable() }
                            if !model.preferences.cliPath.isEmpty {
                                Button(t("자동 찾기", "Find automatically")) { model.updatePreferences { $0.cliPath = "" } }
                            }
                        }.disabled(model.isLoggingIn)
                    }
                    if model.selectedProfile.provider == .codex {
                        TextField(t("계정 폴더 (기본 로그인은 비워 두기)", "Account folder (leave blank for default sign-in)"), text: $configDirectoryDraft)
                            .textFieldStyle(.roundedBorder)
                        Button(t("계정 폴더 적용", "Apply account folder")) { model.setConfigDirectory(configDirectoryDraft) }
                            .disabled(configDirectoryDraft == model.selectedProfile.configDirectory || model.isLoggingIn)
                        if model.isLoggingIn {
                            Button(t("로그인 취소", "Cancel sign-in")) { model.cancelLogin() }
                        } else {
                            Button(model.snapshot == nil ? t("ChatGPT로 로그인", "Sign in with ChatGPT") : t("다른 계정으로 로그인", "Sign in with another account")) { model.login() }
                                .disabled(model.isRunning)
                        }
                        Text(t("별도 계정은 서로 다른 절대 폴더 경로를 지정한 뒤 로그인하세요. 비워 두면 기존 Codex CLI 계정을 사용하며 로그인 시 그 계정이 변경됩니다.",
                               "For separate accounts, choose a different absolute folder path before signing in. A blank path uses the existing Codex CLI account, which sign-in will change."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else if model.selectedProfile.provider == .antigravity {
                        Toggle(t("Antigravity CLI로 자동 조회", "Automatically read through Antigravity CLI"), isOn: Binding(
                            get: { model.selectedProfile.allowAntigravityCLI }, set: { value in model.updateSelectedProfile { $0.allowAntigravityCLI = value } }))
                        Text(t("켜면 갱신할 때 agy /usage를 실행합니다. CLI 1.1.11 이상이 필요하며 사용자의 CLI 설정에 따라 MCP·훅도 실행될 수 있습니다. 별도 프로세스로 분리된 확장은 조회 종료 후에도 남을 수 있습니다. 계정 신원은 반환되지 않아 계정별 기록과 알림은 제공하지 않습니다.",
                               "When enabled, each refresh runs agy /usage. CLI 1.1.11 or newer is required. Your CLI settings may also run MCP servers and hooks; detached extensions can remain after the read finishes. The response has no account identity, so account history and alerts are unavailable."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        TextField(t("사용량 JSON 파일", "Usage JSON file"), text: $configDirectoryDraft)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button(t("JSON 파일 선택", "Choose JSON file")) { model.chooseUsageReport() }
                            Button(t("파일 경로 적용", "Apply file path")) { model.setConfigDirectory(configDirectoryDraft) }
                                .disabled(configDirectoryDraft == model.selectedProfile.configDirectory)
                        }
                        Text(t("자동 조회를 끄거나 조회가 실패하면 선택한 /usage JSON 보고서를 읽습니다. 파일에 제공된 Gemini 주간 한도만 읽으며 15분 이내의 보고서만 표시합니다. 파일 수정 시각은 서비스 조회 시각을 증명하지 않습니다. 이전 보고서를 복사하거나 수정시각만 바꾸어 재사용하지 마세요.",
                               "When automatic reading is off or fails, reads the selected /usage JSON report. Only the reported Gemini weekly allowance in a file from the last 15 minutes is shown. The file modification time does not prove when usage was fetched. Do not reuse an older report by copying it or changing its timestamp."))
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(8)
            }
        }
        .onAppear { configDirectoryDraft = model.selectedProfile.configDirectory }
        .onChange(of: model.selectedProfile.id) { _ in configDirectoryDraft = model.selectedProfile.configDirectory }
        .onChange(of: model.selectedProfile.configDirectory) { value in configDirectoryDraft = value }
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
    private var tokenMeasurementExplanation: String {
        switch model.selectedProfile.provider {
        case .claude: return t("이 저장된 연결은 현재 지원하지 않습니다.", "This saved connection is unavailable.")
        case .codex:
            if model.tokenMeasurementSource != .newSession {
                let source = model.tokenMeasurementSource == .codexRecentSessions ?
                    t("선택한 계정 폴더에서 최근 30일에 생성한 Codex 세션을 자동 관측합니다. 더 오래된 세션은 파일을 선택해 주세요. 폴더를 비우면 CODEX_HOME 또는 기본 .codex를 사용합니다. ", "Automatically observes Codex sessions created in the last 30 days in the selected account folder. Select a file for an older session. Uses CODEX_HOME or the default .codex folder when blank. ") :
                    t("직접 선택한 Codex 세션 파일을 관측합니다. ", "Observes the Codex session file you select. ")
                return source + t("메시지 평균은 같은 메시지의 출력 토큰 수와 시작·완료 시간으로 계산합니다. 턴 평균은 출력 토큰 수를 턴 경과 시간으로 나누므로 도구·승인 대기를 포함합니다. 진행 중 값은 마지막 기록 시점까지만 반영하며 실시간 생성 속도가 아닙니다. 최근 15분 기록만 표시하고 계정 신원은 확인하지 않습니다. 대화 내용은 표시·저장하지 않으며 필요한 필드가 없으면 —로 표시합니다.",
                    "Message averages use the same message's output tokens and start/end times. Turn averages divide output tokens by elapsed turn time, including tool and approval waits. In-progress values stop at the last record and are not live generation speed. Shows only records from the last 15 minutes, without verifying account identity. Conversation content is not displayed or stored; missing fields show —.")
            }
            return t("출력 토큰 수를 응답 스트림의 시작부터 완료까지 시간으로 나눈 평균입니다. 아래 명령으로 시작한 새 Codex CLI 세션만 측정하며 이미 실행 중인 Codex Desktop·CLI 세션은 관찰하지 않습니다. 프로필별 측정 범위이며 서버의 계정 신원을 증명하지 않습니다.",
                     "Averages output tokens from response-stream start to completion. Measures only new Codex CLI sessions started with the command below, not existing Codex Desktop or CLI sessions. The measurement is scoped to this profile, without proving server account identity.")
        case .antigravity:
            return t("Antigravity headless 세션의 완료된 응답 단계가 보고한 출력 토큰 수와 단계 소요 시간으로 계산합니다. 새로 시작한 한 세션만 측정하며 기존 앱·CLI 세션을 관찰하지 않습니다. 측정 연결은 계정 신원을 증명하지 않으며 시각은 단계 수신 시각입니다.",
                     "Uses output tokens and duration reported by a completed response step in a new Antigravity headless session. It does not observe existing app or CLI sessions. This measurement connection does not prove account identity; timestamps show when the step was received.")
        }
    }
    private var tokenLaunchExplanation: String {
        switch model.selectedProfile.provider {
        case .claude: return ""
        case .codex:
            return t("아래 명령은 새 Codex CLI를 시작합니다. 선택한 계정 폴더와 이 실행에만 적용되는 trace 설정을 사용하며 설정 파일을 저장하지 않습니다. 기존 모니터링 설정을 대신하므로 조직의 수집 정책을 유지해야 하는 세션에는 적용하지 마세요.",
                     "This starts a new Codex CLI using the selected account folder and trace settings for that process only, without saving configuration files. It replaces monitoring settings for that process; do not use it when organizational collection settings must remain in force.")
        case .antigravity:
            return t("아래 명령은 작업 내용을 입력받아 실제 Antigravity 작업을 실행하므로 토큰과 비용을 사용할 수 있습니다. 사용자의 CLI 설정에 따라 MCP·훅도 실행됩니다. 작업 출력은 터미널에 그대로 표시하며 측정 수신기에는 허용된 숫자와 시간만 보냅니다.",
                     "This command asks for a task and runs a real Antigravity session, which may use tokens and incur cost. Your CLI settings can also run MCP servers and hooks. Task output passes through to the terminal; only allowed numeric and timing fields go to the measurement receiver.")
        }
    }
    private func row(_ title: String, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).monospacedDigit() }
    }
}
