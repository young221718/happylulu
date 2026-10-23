import AppKit
import AIUsageIntegration
import AppPluginHost

@main
struct CodexSymbolCheck {
    @MainActor static func main() throws {
        guard let png = CodexMenuBarIcon.loadPNG(), let glyph = NSImage(data: png),
              let source = NSBitmapImageRep(data: png) else { fatalError("Missing official Codex glyph") }
        precondition(source.pixelsWide == 32 && source.pixelsHigh == 32)
        for scale in [1, 2] {
            let bitmap = raster(glyph, side: 16 * scale)
            let footprint = checkGlyph(bitmap)
            print("PASS Codex glyph \(scale)x: \(bitmap.pixelsWide)px, alpha footprint \(footprint)")
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let template = PluginMenuBarItem(id: "codex", title: "72%", accessibilityLabel: "Codex weekly remaining 72%",
            iconPNG: png, iconIsTemplate: true)
        for dark in [false, true] {
            for highlighted in [false, true] {
                let title = PluginMenuBarTitle.attributed(base: "Leave 18:00", items: [template], font: font,
                    appearance: NSAppearance(named: dark ? .darkAqua : .aqua), highlighted: highlighted)
                let attachment = attachment(title)
                precondition(attachment.bounds == NSRect(x: 0, y: -4, width: 16, height: 16))
                let bitmap = raster(attachment.image!, side: 32)
                _ = checkGlyph(bitmap)
                let expected: CGFloat = dark || highlighted ? 1 : 0
                for y in 0..<32 {
                    for x in 0..<32 {
                        let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                        if color.alphaComponent > 0.9 {
                            precondition(abs(color.redComponent - expected) < 0.01)
                            precondition(abs(color.greenComponent - expected) < 0.01)
                            precondition(abs(color.blueComponent - expected) < 0.01)
                        }
                    }
                }
                precondition(title.string.contains("72%") && !title.string.contains("Codex"))
            }
        }
        print("PASS template attachment: light/dark and normal/highlighted ink, 16pt baseline, inline percentage")

        let red = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor.red.setFill(); rect.fill(); return true
        }
        let redPNG = NSBitmapImageRep(data: red.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        let original = PluginMenuBarItem(id: "color", title: "Color", accessibilityLabel: "Color", iconPNG: redPNG)
        precondition(!original.iconIsTemplate)
        let colored = attachment(PluginMenuBarTitle.attributed(base: "", items: [original], font: font,
            appearance: NSAppearance(named: .darkAqua), highlighted: true))
        let color = raster(colored.image!, side: 14).colorAt(x: 7, y: 7)!.usingColorSpace(.deviceRGB)!
        precondition(color.redComponent > 0.99 && color.greenComponent < 0.01 && color.blueComponent < 0.01)
        precondition(colored.bounds == NSRect(x: 0, y: -3, width: 14, height: 14))
        print("PASS generic plugin PNG: original color and 14pt bounds preserved")

        let suite = "local.happylulu.codex-symbol-check." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var reads = 0
        let model = AIUsageModel(defaults: defaults, iconProvider: { reads += 1; return png })
        model.updatePreferences { $0.labelFormat = .icon }
        precondition(model.menuBarPreview.iconIsTemplate && model.menuBarPreview.title == "—")
        precondition(model.menuBarPreview.accessibilityLabel.contains("Codex"))
        model.updatePreferences { $0.labelFormat = .named }
        precondition(model.menuBarPreview.iconPNG == nil && !model.menuBarPreview.iconIsTemplate)
        model.updatePreferences { $0.labelFormat = .percentage }
        precondition(model.menuBarPreview.iconPNG == nil && !model.menuBarPreview.iconIsTemplate)
        model.updatePreferences { $0.labelFormat = .icon }
        precondition(model.menuBarPreview.iconPNG == png && reads == 1)
        let invalid = AIUsageModel(defaults: defaults, iconProvider: { Data("invalid".utf8) })
        precondition(invalid.menuBarPreview.iconPNG == nil && invalid.menuBarPreview.title == "Codex —"
            && invalid.preferences.labelFormat == .icon)
        print("PASS Codex model: text/icon/percentage selection, accessibility, one cached glyph, invalid-image fallback; isolated preferences")
    }

    @MainActor private static func raster(_ image: NSImage, side: Int) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: side, height: side))
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    @MainActor private static func checkGlyph(_ bitmap: NSBitmapImageRep) -> String {
        let side = bitmap.pixelsWide
        precondition(bitmap.colorAt(x: 0, y: 0)!.alphaComponent == 0)
        precondition(bitmap.colorAt(x: side / 2, y: side / 2)!.alphaComponent < 0.1)
        var ink = 0, minX = side, maxX = 0, minY = side, maxY = 0
        for y in 0..<side {
            for x in 0..<side {
                let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                if color.alphaComponent > 0.1 {
                    ink += 1; minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                    precondition(abs(color.redComponent - color.greenComponent) < 0.01)
                    precondition(abs(color.greenComponent - color.blueComponent) < 0.01)
                }
            }
        }
        precondition(ink > side * side / 6 && ink < side * side * 3 / 5)
        precondition(maxX - minX + 1 >= side * 3 / 4 && maxY - minY + 1 >= side * 3 / 4)
        return "x=\(minX)...\(maxX),y=\(minY)...\(maxY),ink=\(ink)"
    }

    @MainActor private static func attachment(_ title: NSAttributedString) -> NSTextAttachment {
        var attachments: [NSTextAttachment] = []
        title.enumerateAttribute(.attachment, in: NSRange(location: 0, length: title.length)) { value, _, _ in
            if let value = value as? NSTextAttachment { attachments.append(value) }
        }
        precondition(attachments.count == 1)
        return attachments[0]
    }
}
