import AppKit
import Combine
import SwiftUI

private struct SettingsTitlebarBrand: View {
    @ObservedObject var appearance: AppearanceModel
    let followsTheme: Bool
    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: LuluBrand.headerIcon).resizable().interpolation(.high).frame(width: 20, height: 20)
            Text("happylulu").font(.system(size: 13, weight: .semibold))
        }
        .padding(.leading, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(followsTheme ? appearance.text : Color(nsColor: .labelColor))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("happylulu")
    }
}

private final class SettingsTitlebarBrandView: NSHostingView<SettingsTitlebarBrand> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Keeps native window controls above the content while sharing its theme background.
@MainActor
final class SettingsWindowChrome {
    private var appearanceObservation: AnyCancellable?

    init(window: NSWindow, appearance: AppearanceModel, mode: LuluMaterialMode = .automatic) {
        let followsTheme = LuluGlass.isSupported && mode == .automatic
        let brand = SettingsTitlebarBrandView(rootView: SettingsTitlebarBrand(appearance: appearance, followsTheme: followsTheme))
        brand.frame = NSRect(x: 0, y: 0, width: 110, height: 24)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = brand
        accessory.layoutAttribute = .left
        window.addTitlebarAccessoryViewController(accessory)

        guard followsTheme else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        // Keep window.title for accessibility and the Window menu. AppKit owns the
        // traffic lights, titlebar dragging and the content layout safe area.
        appearanceObservation = appearance.$preferences.sink { [weak window] preferences in
            window?.isOpaque = true
            window?.backgroundColor = preferences.palette == .nativeGlass
                ? .windowBackgroundColor : AppearanceModel.nsColor(preferences.colors[.background]!)
        }
    }
}
