import SwiftUI
import AppPluginHost

public struct CPURunnerSettingsView: View {
    @ObservedObject private var model: CPURunnerController
    private let localize: PluginLocalizer

    public init(model: CPURunnerController, localize: @escaping PluginLocalizer) {
        self.model = model; self.localize = localize
    }

    public var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text(localize("표시 방식", "Presentation")).font(.headline)
                        .frame(width: 112, alignment: .leading)
                    Text(model.presentation == .owlOrbit
                        ? localize("CPU에 따라 회전", "Rotates with CPU activity")
                        : localize("CPU에 따라 달리기", "Runs with CPU activity"))
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    Picker(localize("표시 방식", "Presentation"), selection: Binding(
                        get: { model.presentation }, set: { model.selectPresentation($0) })) {
                        Text(localize("부엉이 눈빛", "Owl orbit")).tag(RunnerPresentation.owlOrbit)
                        Text(localize("동물", "Animal")).tag(RunnerPresentation.animal)
                    }.labelsHidden().frame(width: 132)
                        .accessibilityLabel(localize("메뉴바 표시 방식", "Menu bar presentation"))
                }
                if model.presentation == .owlOrbit {
                    VStack(spacing: 8) {
                        orbitColorRow(localize("시작색", "Start color"), start: true)
                        orbitColorRow(localize("끝색", "End color"), start: false)
                        HStack {
                            Spacer()
                            Button(localize("기본색 복원", "Restore colors")) { model.setOrbitPalette(.standard) }
                                .controlSize(.small).disabled(model.palette == .standard)
                        }
                    }
                }
                if model.presentation == .animal {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(localize("캐릭터", "Character")).font(.headline)
                            Text(localize("달릴 친구를 골라 주세요.", "Choose your little runner."))
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(width: 112, alignment: .leading)
                        HStack(spacing: 14) {
                            ForEach(RunnerAnimal.allCases) { animal in
                                VStack(spacing: 5) {
                                    Image(nsImage: RunnerArtwork.image(for: animal, frame: 0))
                                        .renderingMode(.template).resizable().scaledToFit()
                                        .frame(width: 39, height: 27)
                                    Text(localize(animal.koreanName, animal.englishName)).font(.caption)
                                }
                                .foregroundStyle(model.animal == animal ? Color.accentColor : Color.secondary)
                                .accessibilityHidden(true)
                            }
                        }.frame(maxWidth: .infinity)
                        Picker(localize("캐릭터", "Character"), selection: Binding(
                            get: { model.animal }, set: { model.selectAnimal($0) })) {
                            ForEach(RunnerAnimal.allCases) { animal in
                                Text(localize(animal.koreanName, animal.englishName)).tag(animal)
                            }
                        }.labelsHidden().frame(width: 132)
                            .accessibilityLabel(localize("러너 캐릭터", "Runner character"))
                    }
                }
                Divider()
                RunnerMetricsDetailView(model: model, localize: localize)
                Text(localize("CPU가 바쁠수록 부엉이 테두리의 빛이 빠르게 회전해요. 동물 모드에서는 빠르게 달려요. 동작 줄이기를 사용하면 움직이지 않아요.",
                    "The light around the owl turns faster as CPU usage rises. Animal mode runs faster. Reduce Motion keeps both still."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(localize("네트워크는 Wi-Fi·유선 인터페이스의 수신·송신 속도입니다. VPN·가상 인터페이스와 인터넷 접속 확인은 포함하지 않습니다. 디스크·배터리는 5초마다 갱신합니다.",
                    "Network shows receive/send rates for Wi-Fi and Ethernet interfaces. VPN, virtual interfaces and Internet access checks are excluded. Disk and battery update every five seconds."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(12)
        }
    }

    private func orbitColorRow(_ label: String, start: Bool) -> some View {
        HStack(spacing: 12) {
            Text(label).frame(width: 112, alignment: .leading)
            LinearGradient(colors: [orbitColor(model.palette.startRGB), orbitColor(model.palette.endRGB)],
                startPoint: .leading, endPoint: .trailing)
                .frame(width: 72, height: 14).clipShape(Capsule())
                .frame(maxWidth: .infinity).accessibilityHidden(true)
            ColorPicker(label, selection: Binding(
                get: { orbitColor(start ? model.palette.startRGB : model.palette.endRGB) },
                set: { value in
                    guard let color = NSColor(value).usingColorSpace(.sRGB) else { return }
                    let components = [color.redComponent, color.greenComponent, color.blueComponent]
                        .map { UInt32((min(1, max(0, $0)) * 255).rounded()) }
                    let rgb = (components[0] << 16) | (components[1] << 8) | components[2]
                    model.setOrbitPalette(PluginOrbitPalette(startRGB: start ? rgb : model.palette.startRGB,
                        endRGB: start ? model.palette.endRGB : rgb))
                }), supportsOpacity: false)
                .labelsHidden().frame(width: 132, alignment: .trailing).accessibilityLabel(label)
        }
    }

    private func orbitColor(_ rgb: UInt32) -> Color {
        Color(nsColor: NSColor(srgbRed: Double((rgb >> 16) & 255) / 255,
            green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, alpha: 1))
    }
}
