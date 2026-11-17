import AppKit
// AX's immutable option key is declared as a C global by the SDK.
@preconcurrency import ApplicationServices
import AppPluginHost
import SwiftUI

struct UtilitySettingsView: View {
    @ObservedObject var model: UtilityController
    let isScroll: Bool
    let localize: PluginLocalizer
    private func t(_ ko: String, _ en: String) -> String { localize(ko, en) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            GroupBox(t("동작 상태", "Status")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(t("상태", "Status"))
                        Spacer()
                        Text(statusText).foregroundStyle(model.status == .active ? Color.green : Color.secondary)
                            .accessibilityIdentifier("utility-status-\(model.descriptor.id)")
                    }
                    if !model.enabled {
                        Text(t("위의 사용 스위치를 켜면 시작합니다.", "Turn on the Use switch above to start."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if isScroll {
                        Divider()
                        HStack {
                            Button(t("손쉬운 사용 설정 열기", "Open Accessibility Settings")) {
                                let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                                _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
                                guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
                                NSWorkspace.shared.open(url)
                            }
                            Button(t("다시 확인", "Check again")) { model.refreshData() }
                                .disabled(!model.enabled)
                        }
                        Text(t("시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 이 앱을 허용해 주세요. 권한을 바꾸면 잠시 후 다시 확인합니다.",
                               "Allow this app in System Settings → Privacy & Security → Accessibility. Permission changes are checked again shortly."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    } else if case .failed = model.status {
                        Button(t("다시 시도", "Try again")) { model.refreshData() }
                    }
                }.padding(8)
            }
            Text(isScroll
                 ? t("라인 방식이며 제스처·관성 단계가 없는 휠 이벤트의 세로·가로 방향을 반전합니다. 물리 장치를 식별하지 않습니다. 트랙패드 보호를 위해 연속·제스처·관성 이벤트는 변경하지 않으므로 부드러운 스크롤 마우스도 반전되지 않을 수 있습니다. 장치 드라이버가 트랙패드를 일반 휠 형식으로 보내면 구분할 수 없습니다. 실제 마우스·트랙패드 동작은 이 Mac에서 별도로 확인해야 합니다.",
                     "Reverses vertical and horizontal line-based wheel events without gesture or momentum phases. Physical devices are not identified. Continuous, gesture and momentum events stay unchanged to protect trackpad scrolling, so smooth-scroll mice may also remain unchanged. A driver that reports trackpad input as a line wheel cannot be distinguished. Verify your mouse and trackpad on this Mac separately.")
                 : t("사용하는 동안 화면이 자동으로 꺼지지 않습니다. 플러그인을 끄거나 앱을 종료하면 원래대로 돌아갑니다. 덮개 닫기·직접 잠자기·잠금은 그대로 동작하며 배터리를 더 사용할 수 있습니다.",
                     "Prevents the display from sleeping automatically while enabled. Turning off the plugin or quitting the app restores normal behavior. Closing the lid, manual sleep and locking still work. Battery use may increase."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }.font(.system(size: 13))
    }

    private var statusText: String {
        switch model.status {
        case .off: t("꺼짐", "Off")
        case .active: t("사용 중", "Active")
        case .permissionRequired: t("손쉬운 사용 권한 필요", "Accessibility permission required")
        case .failed(let code): t("시작하지 못함 (\(code))", "Could not start (\(code))")
        }
    }
}
