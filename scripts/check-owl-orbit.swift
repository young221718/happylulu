import AppKit
import AfterSixCore
import AppPluginCore
import AppPluginHost
import Combine
import CryptoKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
private final class OrbitProvider: PluginMenuBarImageProviding {
    let descriptor = PluginDescriptor(id: "orbit-fixture", name: "Orbit fixture")
    let enabled = true
    let isRunning = false
    let connectionState = PluginConnectionState.ready
    var changes: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var imageChanges: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var menuBarImage: PluginMenuBarImage?
    var baseIconEffect: PluginBaseIconEffect? = .orbit(phase: 0.25)
    var baseIconAccessibilityLabel: String? { "Owl CPU 35%" }
    init(image: PluginMenuBarImage? = nil) { menuBarImage = image }
    func start() {}
    func stop() {}
    func refreshData() {}
}

@main
struct OwlOrbitChecks {
    struct Failure: Error, CustomStringConvertible { let description: String }
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var checks = 0
        func expect(_ condition: Bool, _ message: String) throws {
            checks += 1
            guard condition else { throw Failure(description: message) }
        }
        let custom = PluginOrbitPalette(startRGB: 0xFF7A59, endRGB: 0xFFC857)
        let colorAppearance = NSAppearance(named: .aqua)!
        let standardColor = LuluBrand.menuBarIcon(for: .regular, vacationEve: false, orbitPhase: 0.25,
            appearance: colorAppearance, highlighted: false)
        let customColor = LuluBrand.menuBarIcon(for: .regular, vacationEve: false, orbitPhase: 0.25,
            appearance: colorAppearance, highlighted: false, palette: custom)
        try expect(png(rep(standardColor, scale: 2)) != png(rep(customColor, scale: 2)),
            "Custom orbit palette did not change pixels at unchanged phase")
        try expect(customColor === LuluBrand.menuBarIcon(for: .regular, vacationEve: false, orbitPhase: 0.25,
            appearance: colorAppearance, highlighted: false, palette: custom), "Custom palette frame was not cached")
        let restored = LuluBrand.menuBarIcon(for: .regular, vacationEve: false, orbitPhase: 0.25,
            appearance: colorAppearance, highlighted: false)
        try expect(restored !== customColor && png(rep(restored, scale: 2)) == png(rep(standardColor, scale: 2)),
            "Changing palette did not invalidate the frame cache")
        let masked = PluginOrbitPalette(startRGB: 0xFF14C9FF, endRGB: 0xFFAD58FF)
        try expect(masked == .standard && restored === LuluBrand.menuBarIcon(for: .regular, vacationEve: false,
            orbitPhase: 0.25, appearance: colorAppearance, highlighted: false, palette: masked),
            "Palette normalization did not preserve the standard frame cache")
        for changed in [PluginOrbitPalette(startRGB: 0x00FF00, endRGB: 0xAD58FF),
                        PluginOrbitPalette(startRGB: 0x14C9FF, endRGB: 0xFF0000)] {
            let image = LuluBrand.menuBarIcon(for: .regular, vacationEve: false, orbitPhase: 0.25,
                appearance: colorAppearance, highlighted: false, palette: changed)
            try expect(png(rep(image, scale: 2)) != png(rep(standardColor, scale: 2)), "One palette endpoint was ignored")
        }
        var firstCycleTimes: [Double] = []
        for frame in 0..<48 {
            let start = ProcessInfo.processInfo.systemUptime
            _ = LuluBrand.menuBarIcon(for: .regular, vacationEve: false, orbitPhase: Double(frame) / 48,
                appearance: NSAppearance(named: .aqua)!, highlighted: false)
            firstCycleTimes.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
        }
        print(String(format: "PERF first orbit cycle: 48 frames, mean %.3f ms, max %.3f ms, first %.3f ms",
            firstCycleTimes.reduce(0, +) / 48, firstCycleTimes.max()!, firstCycleTimes[0]))
        for state in LuluDisplayState.allCases {
            for vacation in [false, true] {
                let base = LuluBrand.menuBarIcon(for: state, vacationEve: vacation)
                let baseBefore = try png(rep(base, scale: 2))
                for dark in [false, true] {
                    let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
                    var signatures = Set<String>()
                    for frame in 0..<48 {
                        let image = LuluBrand.menuBarIcon(for: state, vacationEve: vacation, orbitPhase: Double(frame) / 48,
                            appearance: appearance, highlighted: false)
                        try expect(image.size == NSSize(width: 26, height: 18) && !image.isTemplate, "Orbit changed canvas/template contract")
                        try expect(image === LuluBrand.menuBarIcon(for: state, vacationEve: vacation,
                            orbitPhase: Double(frame) / 48, appearance: appearance, highlighted: false), "Orbit cache did not reuse frame")
                        for scale in [1, 2] {
                            let source = rep(base, scale: scale), pixels = rep(image, scale: scale)
                            var alphaStable = true, eyeStable = true, accessoriesStable = true, borderUnlit = true, premultiplied = true
                            var colorPixels = 0
                            for y in 0..<pixels.pixelsHigh {
                                for x in 0..<pixels.pixelsWide {
                                    let a = source.bitmapData![y * source.bytesPerRow + x * 4 + 3]
                                    let offset = y * pixels.bytesPerRow + x * 4
                                    let bytes = pixels.bitmapData!
                                    alphaStable = alphaStable && bytes[offset + 3] == a
                                    premultiplied = premultiplied && bytes[offset] <= a && bytes[offset + 1] <= a && bytes[offset + 2] <= a
                                    let colored = abs(Int(bytes[offset]) - Int(bytes[offset + 2])) > 4
                                        || abs(Int(bytes[offset + 1]) - Int(bytes[offset + 2])) > 4
                                    if a > 0 && colored { colorPixels += 1 }
                                    let sx = (Double(x) + 0.5) / Double(scale) * 144 / 26
                                    let sy = (Double(y) + 0.5) / Double(scale) * 100 / 18
                                    let eye = ((27...57).contains(sx) || (87...117).contains(sx)) && (35...70).contains(sy)
                                    let beak = (60...84).contains(sx) && (69...92).contains(sy)
                                    if a > 0 && (eye || beak) {
                                        let foreground: UInt8 = dark ? a : 0
                                        eyeStable = eyeStable && bytes[offset] == foreground
                                            && bytes[offset + 1] == foreground && bytes[offset + 2] == foreground
                                    }
                                    if vacation && y < 5 * scale { accessoriesStable = accessoriesStable && !colored }
                                    if x == 0 || y == 0 || x == pixels.pixelsWide - 1 || y == pixels.pixelsHigh - 1 {
                                        borderUnlit = borderUnlit && !(a > 0 && colored)
                                    }
                                }
                            }
                            try expect(alphaStable, "Owl outline/eye/accessory alpha moved: \(state) holiday\(vacation) frame\(frame) \(scale)x")
                            try expect(premultiplied, "Nonpremultiplied RGB changed the composited owl silhouette")
                            try expect(eyeStable, "Eye expression, pupil or beak changed")
                            try expect(accessoriesStable, "Vacation hat was recolored")
                            try expect(borderUnlit, "Glow reached canvas boundary")
                            if !vacation { try expect(colorPixels > 0, "Moving light disappeared from regular owl") }
                            if frame % 12 == 0 {
                                let composited = try bitmap(width: pixels.pixelsWide, height: pixels.pixelsHigh) {
                                    image.draw(in: NSRect(x: 0, y: 0, width: pixels.pixelsWide, height: pixels.pixelsHigh))
                                }
                                var compositedAlphaStable = true
                                for y in 0..<pixels.pixelsHigh {
                                    for x in 0..<pixels.pixelsWide {
                                        compositedAlphaStable = compositedAlphaStable
                                            && composited.bitmapData![y * composited.bytesPerRow + x * 4 + 3]
                                                == source.bitmapData![y * source.bytesPerRow + x * 4 + 3]
                                    }
                                }
                                try expect(compositedAlphaStable, "Native image compositing changed outline/eye support")
                            }
                            if state == .regular && !vacation {
                                let folder = output.appendingPathComponent(dark ? "frames-dark" : "frames-light")
                                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                                try png(pixels).write(to: folder.appendingPathComponent(String(format: "frame-%02d-%dx.png", frame, scale)))
                            }
                        }
                        signatures.insert(SHA256.hash(data: try png(rep(image, scale: 2))).description)
                    }
                    try expect(signatures.count >= (vacation ? 30 : 46), "Light failed to travel around the eye rim")
                    let zero = LuluBrand.menuBarIcon(for: state, vacationEve: vacation, orbitPhase: 0, appearance: appearance, highlighted: false)
                    let end = LuluBrand.menuBarIcon(for: state, vacationEve: vacation, orbitPhase: 1, appearance: appearance, highlighted: false)
                    try expect(zero === end, "Orbit loop did not close exactly")
                    try expect(zero === LuluBrand.menuBarIcon(for: state, vacationEve: vacation,
                        orbitPhase: .nan, appearance: appearance, highlighted: false), "Invalid phase was not bounded")
                }
                try expect(baseBefore == png(rep(base, scale: 2)), "Orbit mutated the original template cache")
            }
        }
        for state in LuluDisplayState.allCases {
            for vacation in [false, true] {
                for dark in [false, true] {
                    for highlighted in [false, true] {
                        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
                        let standard = LuluBrand.menuBarIcon(for: state, vacationEve: vacation, orbitPhase: 0.25,
                            appearance: appearance, highlighted: highlighted)
                        let customImage = LuluBrand.menuBarIcon(for: state, vacationEve: vacation, orbitPhase: 0.25,
                            appearance: appearance, highlighted: highlighted, palette: custom)
                        for scale in [1, 2] {
                            let base = rep(standard, scale: scale), pixels = rep(customImage, scale: scale)
                            var shapeStable = true, unaffectedStable = true, premultiplied = true
                            for y in 0..<pixels.pixelsHigh {
                                for x in 0..<pixels.pixelsWide {
                                    let offset = y * pixels.bytesPerRow + x * 4
                                    let source = base.bitmapData!, target = pixels.bitmapData!
                                    shapeStable = shapeStable && target[offset + 3] == source[offset + 3]
                                    premultiplied = premultiplied && target[offset] <= target[offset + 3]
                                        && target[offset + 1] <= target[offset + 3] && target[offset + 2] <= target[offset + 3]
                                    if source[offset] == source[offset + 1] && source[offset + 1] == source[offset + 2] {
                                        unaffectedStable = unaffectedStable && (0..<3).allSatisfy { target[offset + $0] == source[offset + $0] }
                                    }
                                }
                            }
                            try expect(shapeStable && unaffectedStable && premultiplied,
                                "Palette change altered shape, decoration, unlit pixels or premultiplied alpha")
                        }
                    }
                }
            }
        }
        let red = PluginOrbitPalette(startRGB: 0xFF0000, endRGB: 0xFF0000)
        for frame in 0..<48 {
            let standard = LuluBrand.menuBarIcon(for: .regular, vacationEve: false, orbitPhase: Double(frame) / 48,
                appearance: colorAppearance, highlighted: false)
            let redImage = LuluBrand.menuBarIcon(for: .regular, vacationEve: false, orbitPhase: Double(frame) / 48,
                appearance: colorAppearance, highlighted: false, palette: red)
            for scale in [1, 2] {
                let base = rep(standard, scale: scale), pixels = rep(redImage, scale: scale)
                var intensityStable = true
                for y in 0..<pixels.pixelsHigh {
                    for x in 0..<pixels.pixelsWide {
                        let offset = y * pixels.bytesPerRow + x * 4
                        intensityStable = intensityStable && pixels.bitmapData![offset] == base.bitmapData![offset + 2]
                            && pixels.bitmapData![offset + 1] == 0 && pixels.bitmapData![offset + 2] == 0
                    }
                }
                try expect(intensityStable, "Palette changed trail position, phase or light strength")
            }
        }
        let aqua = NSAppearance(named: .aqua)!, darkAqua = NSAppearance(named: .darkAqua)!
        let highlighted = LuluBrand.menuBarIcon(for: .regular, vacationEve: false, orbitPhase: 0.25, appearance: aqua, highlighted: true)
        let dark = LuluBrand.menuBarIcon(for: .regular, vacationEve: false, orbitPhase: 0.25, appearance: darkAqua, highlighted: false)
        try expect(png(rep(highlighted, scale: 2)) == png(rep(dark, scale: 2)), "Highlight did not preserve white owl contrast")
        let group = PluginMenuBarImageGroup(), effect = OrbitProvider()
        group.setProviders([effect])
        try expect(group.baseIconEffect == .orbit(phase: 0.25), "Host group dropped base effect")
        effect.baseIconEffect = .orbit(phase: 0.25, palette: custom)
        try expect(group.baseIconEffect == .orbit(phase: 0.25, palette: custom), "Host group dropped a live palette change")
        effect.baseIconEffect = .orbit(phase: 0.25)
        try expect(group.accessibilityLabels == ["Owl CPU 35%"], "Host group dropped effect accessibility")
        let base = LuluBrand.menuBarIcon(for: .regular)
        try expect(group.image(base: base) === base, "Base effect added a detached image")
        let appended = OrbitProvider(image: PluginMenuBarImage(image: base, accessibilityLabel: "Append fixture"))
        appended.baseIconEffect = .orbit(phase: 0.5)
        group.setProviders([effect, appended])
        try expect(group.baseIconEffect == .orbit(phase: 0.25), "Host group did not use the first effect")
        try expect(group.image(base: base).size.width == 56, "Existing appended-image contract changed")
        group.setProviders([])
        try expect(group.baseIconEffect == nil && group.accessibilityLabels.isEmpty, "Removed effect remained in host output")
        try png(try board()).write(to: output.appendingPathComponent("owl-orbit-comparison.png"))
        try exportCustomFrames(palette: custom, to: output)
        try png(try colorBoard(palette: custom)).write(to: output.appendingPathComponent("owl-colors-comparison.png"))
        try makeGIF(output.appendingPathComponent("owl-orbit-speed-comparison.gif"))
        print("PASS \(checks) owl orbit checks: original alpha, fixed pupils/expressions/beak/holiday hat, moving light, clipping, 1x/2x, exact loop, palette cache/endpoint updates, unchanged trail strength, highlight contrast and host effect lifecycle")
        print("Evidence: \(output.path)")
    }

    @MainActor static func rep(_ image: NSImage, scale: Int) -> NSBitmapImageRep {
        image.representations.compactMap { $0 as? NSBitmapImageRep }.first { $0.pixelsWide == 26 * scale }!
    }
    static func png(_ rep: NSBitmapImageRep) throws -> Data {
        guard let data = rep.representation(using: .png, properties: [:]) else { throw Failure(description: "PNG encoding") }
        return data
    }
    @MainActor static func bitmap(width: Int, height: Int, draw: () -> Void) throws -> NSBitmapImageRep {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep) else { throw Failure(description: "Bitmap allocation") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        draw(); NSGraphicsContext.restoreGraphicsState()
        return rep
    }
    @MainActor static func label(_ text: String, x: CGFloat, y: CGFloat, dark: Bool, size: CGFloat = 16) {
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size),
            .foregroundColor: dark ? NSColor.white : NSColor.black])
    }
    @MainActor static func drawOwl(phase: Double, dark: Bool, vacation: Bool = false, x: CGFloat, y: CGFloat, zoom: CGFloat,
                                  palette: PluginOrbitPalette = .standard) {
        let image = LuluBrand.menuBarIcon(for: .regular, vacationEve: vacation, orbitPhase: phase,
            appearance: NSAppearance(named: dark ? .darkAqua : .aqua)!, highlighted: false, palette: palette)
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: NSRect(x: x, y: y, width: 26 * zoom, height: 18 * zoom))
    }
    @MainActor static func exportCustomFrames(palette: PluginOrbitPalette, to output: URL) throws {
        for dark in [false, true] {
            let folder = output.appendingPathComponent(dark ? "frames-custom-dark" : "frames-custom-light")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for frame in 0..<48 {
                let image = LuluBrand.menuBarIcon(for: .regular, vacationEve: false, orbitPhase: Double(frame) / 48,
                    appearance: NSAppearance(named: dark ? .darkAqua : .aqua)!, highlighted: false, palette: palette)
                for scale in [1, 2] {
                    try png(rep(image, scale: scale)).write(to: folder.appendingPathComponent(String(format: "frame-%02d-%dx.png", frame, scale)))
                }
            }
        }
    }
    @MainActor static func colorBoard(palette: PluginOrbitPalette) throws -> NSBitmapImageRep {
        try bitmap(width: 1100, height: 560) {
            for (row, dark) in [false, true].enumerated() {
                let y = CGFloat(280 - row * 280)
                (dark ? NSColor(calibratedWhite: 0.10, alpha: 1) : .white).setFill()
                NSRect(x: 0, y: y, width: 1100, height: 280).fill()
                label(dark ? "Dark · editable start / end colors" : "Light · editable start / end colors", x: 24, y: y + 246, dark: dark, size: 20)
                for (column, value) in [PluginOrbitPalette.standard, palette].enumerated() {
                    let x = CGFloat(60 + column * 530)
                    for (position, phase) in [0.0, 0.5].enumerated() {
                        drawOwl(phase: phase, dark: dark, x: x + CGFloat(position * 230), y: y + 81, zoom: 7, palette: value)
                        drawOwl(phase: phase, dark: dark, x: x + CGFloat(position * 230) + 78, y: y + 40, zoom: 1, palette: value)
                    }
                    label(column == 0 ? "Standard · 14C9FF / AD58FF" : "Custom · FF7A59 / FFC857", x: x + 70, y: y + 12, dark: dark, size: 14)
                }
            }
        }
    }
    @MainActor static func board() throws -> NSBitmapImageRep {
        try bitmap(width: 1100, height: 560) {
            for (row, dark) in [false, true].enumerated() {
                let y = CGFloat(280 - row * 280)
                (dark ? NSColor(calibratedWhite: 0.10, alpha: 1) : .white).setFill()
                NSRect(x: 0, y: y, width: 1100, height: 280).fill()
                label(dark ? "Dark · fixed owl / moving rim light" : "Light · fixed owl / moving rim light", x: 24, y: y + 246, dark: dark, size: 20)
                for frame in 0..<4 {
                    let x = CGFloat(24 + frame * 220)
                    drawOwl(phase: Double(frame) / 4, dark: dark, x: x, y: y + 78, zoom: 7)
                    drawOwl(phase: Double(frame) / 4, dark: dark, x: x + 74, y: y + 34, zoom: 1)
                    label("\(frame * 90)°", x: x + 76, y: y + 11, dark: dark, size: 12)
                }
                drawOwl(phase: 0.7, dark: dark, vacation: true, x: 905, y: y + 105, zoom: 6)
                drawOwl(phase: 0.7, dark: dark, vacation: true, x: 970, y: y + 66, zoom: 1)
                label("Vacation eve", x: 915, y: y + 35, dark: dark, size: 13)
            }
        }
    }
    @MainActor static func makeGIF(_ url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 96, nil) else {
            throw Failure(description: "GIF allocation")
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<96 {
            let rep = try bitmap(width: 900, height: 430) {
                for (row, dark) in [false, true].enumerated() {
                    let y = CGFloat(215 - row * 215)
                    (dark ? NSColor(calibratedWhite: 0.1, alpha: 1) : .white).setFill()
                    NSRect(x: 0, y: y, width: 900, height: 215).fill()
                    for (column, cycle) in [96, 48, 24].enumerated() {
                        let x = CGFloat(42 + column * 300)
                        let phase = Double(frame % cycle) / Double(cycle)
                        drawOwl(phase: phase, dark: dark, x: x, y: y + 70, zoom: 7)
                        drawOwl(phase: phase, dark: dark, x: x + 80, y: y + 29, zoom: 1)
                        label(["Low CPU · slow", "Medium CPU", "High CPU · fast"][column], x: x + 21, y: y + 5, dark: dark, size: 14)
                    }
                }
            }
            CGImageDestinationAddImage(destination, rep.cgImage!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.06]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw Failure(description: "GIF encoding") }
    }
}
