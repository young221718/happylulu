import Foundation
import Combine
import AppPluginCore
import AppKit
import SwiftUI

public enum PluginConnectionState: Equatable { case off, setup, connecting, ready, attention }

/// A plugin owns its settings and lifecycle; the catalog never understands its wire API.
@MainActor
public protocol PluginController: AnyObject {
    var descriptor: PluginDescriptor { get }
    var changes: AnyPublisher<Void, Never> { get }
    var enabled: Bool { get }
    var isRunning: Bool { get }
    var connectionState: PluginConnectionState { get }
    func start()
    func stop()
    func refreshData()
}

public struct PluginRegistration: Identifiable {
    public let id: String
    public let controller: any PluginController
    public let adapter: any FeatureAdapter
    public let symbol: String
    public let setEnabled: (@MainActor (Bool) -> Void)?
    public let summaryKorean: String
    public let summaryEnglish: String
    @MainActor
    public init(controller: any PluginController, adapter: any FeatureAdapter, symbol: String, summary: String,
         englishSummary: String? = nil, setEnabled: (@MainActor (Bool) -> Void)? = nil) {
        id = controller.descriptor.id; self.controller = controller; self.adapter = adapter
        self.setEnabled = setEnabled
        self.symbol = symbol; self.summaryKorean = summary; self.summaryEnglish = englishSummary ?? summary
    }
}

public typealias PluginLocalizer = @MainActor (String, String) -> String

@MainActor
public struct PluginHostContext {
    public let registry: PluginRegistry
    public let presentations: PluginSettingsPresentationRegistry
    public let register: @MainActor (PluginRegistration) throws -> Void
    public let localize: PluginLocalizer
    private let rollback: @MainActor (String) -> Void
    public init(registry: PluginRegistry, presentations: PluginSettingsPresentationRegistry,
                register: @escaping @MainActor (PluginRegistration) throws -> Void,
                rollback: @escaping @MainActor (String) -> Void, localize: @escaping PluginLocalizer) {
        self.registry = registry; self.presentations = presentations
        self.register = register; self.rollback = rollback; self.localize = localize
    }

    /// One module owns one ID. Failed installation removes only its new registrations.
    public func install(_ module: any PluginModule.Type) throws {
        let id = module.id
        guard !registry.descriptors.contains(where: { $0.id == id }), !presentations.contains(id) else {
            throw PluginFailure.duplicatePlugin
        }
        var registered = false
        let scoped = PluginHostContext(registry: registry, presentations: presentations, register: { registration in
            guard registration.id == id, !registered else { throw PluginFailure.configuration }
            try register(registration)
            registered = true
        }, rollback: rollback, localize: localize)
        do {
            try module.register(in: scoped)
            guard registered else { throw PluginFailure.configuration }
        } catch {
            if registered { rollback(id) }
            if registry.descriptors.contains(where: { $0.id == id }) { registry.unregister(id) }
            presentations.unregister(id)
            throw error
        }
    }
}

@MainActor
public protocol PluginModule {
    static var id: String { get }
    static var catalogMetadata: PluginModuleMetadata? { get }
    static func register(in context: PluginHostContext) throws
}

/// Optional modules describe themselves without importing provider code into the app.
public struct PluginModuleMetadata: Sendable {
    public let name: String
    public let englishName: String
    public let author: String
    public let summary: String
    public let englishSummary: String
    public let symbol: String
    public let providesUsage: Bool
    public init(name: String, englishName: String? = nil, author: String, summary: String, englishSummary: String,
                symbol: String, providesUsage: Bool = false) {
        self.name = name; self.englishName = englishName ?? name; self.author = author; self.summary = summary
        self.englishSummary = englishSummary; self.symbol = symbol; self.providesUsage = providesUsage
    }
}
public extension PluginModule { static var catalogMetadata: PluginModuleMetadata? { nil } }

public struct PluginMenuBarItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let accessibilityLabel: String
    public let iconPNG: Data?
    public let iconIsTemplate: Bool
    public init(id: String, title: String, accessibilityLabel: String, iconPNG: Data? = nil,
                iconIsTemplate: Bool = false) {
        self.id = id; self.title = title; self.accessibilityLabel = accessibilityLabel
        self.iconPNG = iconPNG; self.iconIsTemplate = iconIsTemplate
    }
}

/// Optional status output. The app renders it without understanding the provider API.
@MainActor
public protocol PluginMenuBarProviding: PluginController {
    var menuBarItem: PluginMenuBarItem? { get }
}

public struct PluginMenuBarImage {
    public let image: NSImage
    public let accessibilityLabel: String
    public init(image: NSImage, accessibilityLabel: String) {
        self.image = image; self.accessibilityLabel = accessibilityLabel
    }
}

/// Animation output bypasses plugin state changes and feature-data invalidation.
public struct PluginOrbitPalette: Equatable, Sendable {
    public let startRGB: UInt32
    public let endRGB: UInt32
    public init(startRGB: UInt32, endRGB: UInt32) {
        self.startRGB = startRGB & 0xFFFFFF
        self.endRGB = endRGB & 0xFFFFFF
    }
    public static let standard = PluginOrbitPalette(startRGB: 0x14C9FF, endRGB: 0xAD58FF)
}

public enum PluginBaseIconEffect: Equatable {
    case orbit(phase: Double, palette: PluginOrbitPalette = .standard)
}

@MainActor
public protocol PluginMenuBarImageProviding: PluginController {
    var menuBarImage: PluginMenuBarImage? { get }
    var imageChanges: AnyPublisher<Void, Never> { get }
    var baseIconEffect: PluginBaseIconEffect? { get }
    var baseIconAccessibilityLabel: String? { get }
}

public extension PluginMenuBarImageProviding {
    var baseIconEffect: PluginBaseIconEffect? { nil }
    var baseIconAccessibilityLabel: String? { nil }
}

/// Live plugin content observes its controller without invalidating host feature data.
@MainActor
public protocol PluginPanelProviding: PluginController {
    var panelView: AnyView { get }
    var panelHeight: CGFloat { get }
}

/// The app keeps one status item; optional providers contribute only image content.
@MainActor
public final class PluginMenuBarImageGroup {
    private var providers: [any PluginMenuBarImageProviding] = []
    private var subscriptions: [AnyCancellable] = []
    private let updates = PassthroughSubject<Void, Never>()
    public var changes: AnyPublisher<Void, Never> { updates.eraseToAnyPublisher() }
    public var baseIconEffect: PluginBaseIconEffect? { providers.compactMap(\.baseIconEffect).first }
    public var accessibilityLabels: [String] {
        providers.flatMap { [$0.menuBarImage?.accessibilityLabel, $0.baseIconAccessibilityLabel].compactMap { $0 } }
    }

    public init() {}

    public func setProviders(_ providers: [any PluginMenuBarImageProviding]) {
        guard self.providers.map(ObjectIdentifier.init) != providers.map(ObjectIdentifier.init) else { return }
        subscriptions.removeAll()
        self.providers = providers
        subscriptions = providers.map { provider in
            provider.imageChanges.sink { [weak self] in self?.updates.send() }
        }
    }

    public func image(base: NSImage) -> NSImage {
        let additions = providers.compactMap { $0.menuBarImage?.image }
        guard !additions.isEmpty else { return base }
        let images = [base] + additions
        let gap: CGFloat = 4
        let size = NSSize(width: images.reduce(0) { $0 + $1.size.width } + gap * CGFloat(additions.count),
                          height: images.map { $0.size.height }.max() ?? base.size.height)
        let image = NSImage(size: size)
        for scale in [1, 2] {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                pixelsWide: Int(ceil(size.width)) * scale, pixelsHigh: Int(ceil(size.height)) * scale,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: rep) else { continue }
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            var x: CGFloat = 0
            for part in images {
                part.draw(in: NSRect(x: x, y: (size.height - part.size.height) / 2,
                                     width: part.size.width, height: part.size.height),
                          from: .zero, operation: .sourceOver, fraction: 1)
                x += part.size.width + gap
            }
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        image.isTemplate = images.allSatisfy(\.isTemplate)
        return image
    }
}

/// Icon-bearing text output stays beside its percentage in the existing title order.
@MainActor
public enum PluginMenuBarTitle {
    public static func attributed(base: String, items: [PluginMenuBarItem], font: NSFont,
                                  appearance: NSAppearance? = nil, highlighted: Bool = false) -> NSAttributedString {
        let dark = (appearance ?? NSAppearance.currentDrawing()).bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let ink = highlighted || dark ? NSColor.white : NSColor.black
        let result = NSMutableAttributedString(string: " " + base, attributes: [.font: font])
        for item in items {
            result.append(NSAttributedString(string: " · ", attributes: [.font: font]))
            if let png = item.iconPNG, let image = NSImage(data: png) {
                let attachment = NSTextAttachment()
                if item.iconIsTemplate {
                    // Text attachments do not inherit the status button's template-image tint.
                    attachment.image = NSImage(size: image.size, flipped: false) { rect in
                        image.draw(in: rect)
                        ink.setFill(); rect.fill(using: .sourceIn)
                        return true
                    }
                } else { attachment.image = image }
                let side: CGFloat = item.iconIsTemplate ? 16 : 14
                attachment.bounds = NSRect(x: 0, y: item.iconIsTemplate ? -4 : -3, width: side, height: side)
                result.append(NSAttributedString(attachment: attachment))
                result.append(NSAttributedString(string: " ", attributes: [.font: font]))
            }
            result.append(NSAttributedString(string: item.title, attributes: [.font: font]))
        }
        return result
    }
}
