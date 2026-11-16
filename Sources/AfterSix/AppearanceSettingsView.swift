import SwiftUI
import AfterSixCore

private typealias AppearanceState<Value> = SwiftUI.State<Value>

@MainActor
struct AppearanceSettingsView: View {
    @ObservedObject var appearance: AppearanceModel
    @AppearanceState private var showingColors = false
    init(appearance: AppearanceModel = .shared) { self.appearance = appearance }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsLayout.betweenSections) {
            if let error = appearance.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            ZStack(alignment: .topTrailing) {
                GroupBox(L("테마", "Theme")) {
                    VStack(alignment: .leading, spacing: 12) {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(AppearancePalette.allCases.filter { $0 != .nativeGlass || AppearanceModel.supportsNativeAppearance }, id: \.self) { palette in
                                let selected = appearance.preferences.palette == palette
                                Button { appearance.selectPalette(palette) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(spacing: 4) {
                                            Text(palette.title).font(.system(size: 12)).lineLimit(1)
                                            Spacer(minLength: 0)
                                            if selected {
                                                Image(systemName: "checkmark.circle.fill").foregroundStyle(appearance.accent)
                                            }
                                        }
                                        palettePreview(palette)
                                    }.padding(8).frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                                        .background(appearance.accent.opacity(selected ? 0.05 : 0.015), in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                                            selected ? appearance.accent : Color.primary.opacity(0.05), lineWidth: selected ? 2 : 1))
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .accessibilityLabel(palette.title)
                                    .accessibilityValue(selected ? L("선택됨", "Selected") : "")
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }.padding(8)
                }
                Button(L("색상 설정…", "Edit colors…")) { showingColors = true }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .foregroundStyle(appearance.preferences.palette == .nativeGlass ? appearance.text.opacity(0.4) : appearance.accent)
                    .disabled(appearance.preferences.palette == .nativeGlass)
                    .padding(.trailing, 10)
            }.disabled(appearance.isReadOnly)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("appearance-theme")
            GroupBox(L("앱 아이콘", "App icon")) {
                VStack(alignment: .leading, spacing: 12) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 86))], spacing: 10) {
                        ForEach(visibleIcons, id: \.self) { icon in
                            let selected = appearance.preferences.icon == icon
                            Button { appearance.selectIcon(icon) } label: {
                                VStack(spacing: 5) {
                                    Image(nsImage: appearance.image(for: icon)).resizable().scaledToFit().frame(width: 48, height: 48)
                                    Text(icon.title).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                                        .frame(height: 28)
                                }.frame(maxWidth: .infinity).frame(height: 94)
                                    .background(appearance.accent.opacity(selected ? 0.05 : 0.015), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                                        selected ? appearance.accent : .clear, lineWidth: 2))
                                    .overlay(alignment: .topTrailing) {
                                        if selected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(appearance.accent)
                                                .padding(5)
                                        }
                                    }
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel(icon.title)
                                .accessibilityValue(selected ? L("선택됨", "Selected") : "")
                                .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    HStack {
                        Button(L("PNG/JPEG 가져오기…", "Import PNG/JPEG…")) { appearance.importIcon() }
                        if appearance.preferences.customImageFilename != nil {
                            Button { appearance.selectIcon(.custom) } label: {
                                Label(L("사용자 이미지", "Custom image"), systemImage: appearance.preferences.icon == .custom ? "checkmark.circle.fill" : "photo")
                            }
                        }
                    }
                    Text(L("최대 20MB · 각 변 최대 8192px. 실행 중 아이콘만 바뀌며 Finder 설치 아이콘은 유지됩니다.", "Up to 20MB and 8192px per side. Changes the running app icon; Finder keeps the installed icon."))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }.disabled(appearance.isReadOnly)
                .accessibilityIdentifier("appearance-icons")
        }.foregroundStyle(appearance.text)
            .sheet(isPresented: $showingColors) { colorSettingsSheet }
    }

    private var colorSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(appearance.preferences.palette == .customTheme ? L("커스텀 색상", "Custom colors") : L("세부 색상", "Colors"))
                .font(.system(size: 16, weight: .semibold))
            ForEach(AppearanceColorRole.allCases, id: \.self) { role in
                AppearanceColorEditor(appearance: appearance, role: role)
            }
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6).fill(appearance.sidebar).frame(width: 35)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("미리보기", "Preview")).font(.headline)
                    Text(L("출퇴근 기록과 설정에 같은 색상을 사용합니다.", "Attendance and settings share these colors."))
                        .font(.callout)
                    Text(L("강조색", "Accent")).foregroundStyle(appearance.accent).font(.caption.bold())
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(appearance.surface)
            }.padding(10).foregroundStyle(appearance.text).background(appearance.background)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            if appearance.hasLowContrast {
                Label(L("글자 대비가 낮습니다. 가독성을 확인해 주세요.", "Low text contrast. Check readability."), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button(L("현재 테마 기본값 복원", "Restore theme defaults")) { appearance.resetColors() }
                Spacer()
                Button(L("완료", "Done")) { showingColors = false }
            }
        }
        .padding(20).frame(width: 420)
        .foregroundStyle(appearance.text).background(appearance.background)
    }

    @ViewBuilder private func palettePreview(_ palette: AppearancePalette) -> some View {
        if palette == .nativeGlass {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(nsColor: .labelColor))
                .frame(maxWidth: .infinity).frame(height: 22)
                .luluGlassSurface(tint: .clear, fallback: Color(nsColor: .controlBackgroundColor),
                                  cornerRadius: 5, usesSystemAppearance: true)
        } else {
            HStack(spacing: 0) {
                ForEach([AppearanceColorRole.sidebar, .background, .accent], id: \.self) { role in
                    Color(nsColor: AppearanceModel.nsColor(previewColor(palette, role: role)))
                }
            }.frame(height: 22).clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }

    private var visibleIcons: [AppearanceIcon] {
        let icons: [AppearanceIcon] = [.original, .happy, .fiery, .money, .sad]
        let selected = appearance.preferences.icon
        return icons.contains(selected) || selected == .custom ? icons : icons + [selected]
    }

    private func previewColor(_ palette: AppearancePalette, role: AppearanceColorRole) -> String {
        guard palette == .customTheme else { return palette.colors[role]! }
        if appearance.preferences.palette == .customTheme { return appearance.preferences.colors[role]! }
        return appearance.preferences.customThemeColors?[role.rawValue] ?? palette.colors[role]!
    }
}

private struct AppearanceColorEditor: View {
    @ObservedObject var appearance: AppearanceModel
    let role: AppearanceColorRole
    @AppearanceState private var draft = ""
    @FocusState private var isFocused: Bool
    var body: some View {
        HStack(spacing: 12) {
            Text(role.title).frame(maxWidth: .infinity, alignment: .leading)
            ColorPicker(role.title, selection: Binding(get: { appearance.color(role) }, set: { appearance.setColor($0, for: role) }), supportsOpacity: false)
                .labelsHidden().accessibilityLabel(role.title)
            TextField("#RRGGBB", text: $draft)
                .font(.system(.body, design: .monospaced)).textFieldStyle(.roundedBorder).frame(width: 110)
                .focused($isFocused).onSubmit { appearance.setColor(draft, for: role) }
                .onChange(of: isFocused) { focused in if !focused { appearance.setColor(draft, for: role) } }
                .onAppear { draft = appearance.hex(role) }
                .onChange(of: appearance.hex(role)) { draft = $0 }
                .accessibilityLabel(role.title + " HEX")
        }
    }
}

private extension AppearancePalette {
    var title: String {
        switch self {
        case .nativeGlass: L("기본", "Default")
        case .offwhiteLilac: L("오프화이트 라일락", "Off-white lilac")
        case .softMint: L("소프트 민트", "Soft mint")
        case .warmStone: L("웜 스톤", "Warm stone")
        case .blueGray: L("블루 그레이", "Blue gray")
        case .dustyLavender: L("더스티 라벤더", "Dusty lavender")
        case .charcoal: L("차콜", "Charcoal")
        case .customTheme: L("커스텀", "Custom")
        }
    }
}
private extension AppearanceIcon {
    var title: String {
        switch self {
        case .original: L("기본 부엉이", "Owl")
        case .happy: L("웃는 부엉이", "Happy owl")
        case .fiery: L("이글이글 부엉이", "Fiery owl")
        case .money: L("돈 좋아 부엉이", "Money owl")
        case .sad: L("우울한 부엉이", "Sad owl")
        case .mint: L("이전 민트", "Previous mint")
        case .blue: L("이전 블루", "Previous blue")
        case .lavender: L("이전 라벤더", "Previous lavender")
        case .graphite: L("이전 그라파이트", "Previous graphite")
        case .custom: L("사용자 이미지", "Custom image")
        }
    }
}
private extension AppearanceColorRole {
    var title: String {
        switch self {
        case .background: L("창 배경", "Window background")
        case .sidebar: L("사이드바", "Sidebar")
        case .surface: L("주요 카드", "Cards")
        case .accent: L("강조색", "Accent")
        case .text: L("본문", "Text")
        }
    }
}
