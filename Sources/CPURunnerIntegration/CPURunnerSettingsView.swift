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
                HStack(spacing: 12) {
                    Text(localize("메모리 압력", "Memory pressure"))
                        .frame(width: 112, alignment: .leading)
                    HStack(spacing: 12) {
                        ForEach(Array([MemoryPressure?.some(.normal), .some(.warning), .some(.critical), nil].enumerated()), id: \.offset) { _, pressure in
                            RunnerMemoryPressureBadge(pressure: pressure, localize: localize)
                        }
                    }.frame(maxWidth: .infinity, alignment: .trailing)
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
                Text(localize("CPU가 높을수록 빠르게 움직이고, 부엉이 테두리 색은 macOS 메모리 압력을 나타내요. 동물 모드의 테두리는 정지해요. 동작 줄이기는 움직임만 멈춰요.",
                    "CPU controls speed. The owl outline color shows macOS memory pressure and stays still in Animal mode. Reduce Motion stops movement."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(localize("메모리 압력은 사용량 비율과 별개예요. macOS가 압력을 제공하지 않으면 회색·미측정으로 표시해요.",
                    "Memory pressure is independent of the percentage used. Unavailable macOS pressure appears gray with an explicit label."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(localize("네트워크는 Wi-Fi·유선 인터페이스의 수신·송신 속도입니다. VPN·가상 인터페이스와 인터넷 접속 확인은 포함하지 않습니다. 디스크·배터리는 5초마다 갱신합니다.",
                    "Network shows receive/send rates for Wi-Fi and Ethernet interfaces. VPN, virtual interfaces and Internet access checks are excluded. Disk and battery update every five seconds."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(12)
        }
    }

}
