import AppKit
import SwiftUI

@MainActor
enum KeepAwakeOwl {
    static func image(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            NSColor.labelColor.setFill()
            let outline = NSBezierPath()
            outline.move(to: NSPoint(x: 1, y: 9)); outline.line(to: NSPoint(x: 2, y: 15))
            outline.line(to: NSPoint(x: 7, y: 12)); outline.line(to: NSPoint(x: 15, y: 12))
            outline.line(to: NSPoint(x: 20, y: 15)); outline.line(to: NSPoint(x: 21, y: 9))
            outline.lineWidth = 1.3; outline.stroke()
            for x: CGFloat in [6, 16] {
                if active {
                    let eye = NSBezierPath(ovalIn: NSRect(x: x - 4, y: 3, width: 8, height: 8))
                    eye.lineWidth = 1.3; eye.stroke()
                    NSBezierPath(ovalIn: NSRect(x: x - 1.5, y: 5.5, width: 3, height: 3)).fill()
                } else {
                    let eye = NSBezierPath()
                    eye.move(to: NSPoint(x: x - 4, y: 6)); eye.line(to: NSPoint(x: x, y: 4))
                    eye.line(to: NSPoint(x: x + 4, y: 6)); eye.lineWidth = 1.5; eye.stroke()
                }
            }
            let beak = NSBezierPath()
            beak.move(to: NSPoint(x: 9, y: 3)); beak.line(to: NSPoint(x: 13, y: 3))
            beak.line(to: NSPoint(x: 11, y: 0)); beak.close(); beak.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
    static func png(active: Bool) -> Data? {
        guard let tiff = image(active: active).tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

struct KeepAwakeControlView: View {
    @ObservedObject var model: KeepAwakeController
    var body: some View {
        Button { model.toggleSession() } label: {
            HStack(spacing: 10) {
                Image(nsImage: KeepAwakeOwl.image(active: model.isKeepAwakeApplied))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.statusText).font(.system(size: 11, weight: .medium))
                    if let deadline = model.deadline {
                        Text(deadline, style: .timer).monospacedDigit().font(.system(size: 10))
                    }
                }
                Spacer(minLength: 0)
                Text(model.isKeepAwakeApplied ? model.localize("중지", "Stop") : model.localize("시작", "Start"))
                    .font(.system(size: 11))
            }.padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.enabled)
        .accessibilityIdentifier("keep-awake-owl-control")
        .accessibilityLabel(model.statusText)
        .accessibilityHint(model.isKeepAwakeApplied ? model.localize("잠자기 방지 요청 해제", "Release keep-awake request")
                           : model.localize("잠자기 방지 요청 시작 또는 재시도", "Start or retry keep-awake request"))
    }
}

struct KeepAwakeSettingsView: View {
    @ObservedObject var model: KeepAwakeController
    private func t(_ ko: String, _ en: String) -> String { model.localize(ko, en) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GroupBox(t("부엉이로 제어", "Owl control")) {
                KeepAwakeControlView(model: model)
            }
            GroupBox(t("유지 옵션", "Keep-awake options")) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker(t("유지 범위", "Prevent idle sleep for"), selection: Binding(get: { model.mode }, set: model.selectMode)) {
                        Text(t("화면과 시스템", "Display and system")).tag(KeepAwakeMode.displayAndSystem)
                        Text(t("시스템만 · 화면 꺼짐 허용", "System only · allow display sleep")).tag(KeepAwakeMode.system)
                    }
                    Picker(t("유지 시간", "Duration"), selection: Binding(get: { model.duration }, set: model.selectDuration)) {
                        Text(t("직접 끌 때까지", "Until stopped")).tag(KeepAwakeDuration.indefinite)
                        Text(t("15분", "15 minutes")).tag(KeepAwakeDuration.minutes15)
                        Text(t("30분", "30 minutes")).tag(KeepAwakeDuration.minutes30)
                        Text(t("1시간", "1 hour")).tag(KeepAwakeDuration.hour)
                        Text(t("2시간", "2 hours")).tag(KeepAwakeDuration.twoHours)
                    }
                    Text(t("실행 중 옵션을 바꾸면 선택한 시간으로 다시 시작합니다. 시간이 끝나면 해제하며, 부엉이를 눌러 다시 시작할 수 있습니다.",
                           "Changing options while running starts a new duration. When the timer ends, the request is released. Click the owl to start again."))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(8)
            }
            Text(t("눈을 뜬 부엉이는 macOS에 잠자기 방지 요청이 적용된 상태이며 실제 화면 켜짐을 측정한 표시는 아닙니다. 닫힌 눈은 중지·시간 종료·실패 상태입니다. 실패 원인은 상태 글자로 확인합니다. 앱 종료·플러그인 끄기는 요청을 해제하며 배터리 사용량이 늘 수 있습니다.",
                   "Open owl eyes mean macOS reports the keep-awake request as applied; they do not measure whether the display is on. Closed eyes mean paused, expired or failed; see the status text for errors. Quitting or disabling releases the request. Battery use may increase."))
            Text(t("덮개 닫힘 동작: 지원 보장 안 됨 · 이 Mac에서 확인하지 않음. 직접 잠자기·덮개 닫기·배터리 부족·과열에 의한 잠자기를 막지 않습니다. 외장 화면을 연결한 덮개 닫힘 사용은 Mac 모델과 Apple의 전원·주변기기 조건을 따라야 합니다.",
                   "Lid-closed operation: not guaranteed · not verified on this Mac. Manual sleep, lid closure, low-battery and thermal sleep are not prevented. Closed-display use with an external display depends on your Mac model and Apple's power and peripheral requirements."))
            Link(t("Apple 잠자기 동작 안내", "Apple sleep behavior"), destination: URL(string: "https://developer.apple.com/library/archive/qa/qa1340/_index.html")!)
        }
        .font(.system(size: 13))
        .fixedSize(horizontal: false, vertical: true)
    }
}
