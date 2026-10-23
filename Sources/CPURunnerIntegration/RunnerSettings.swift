import Foundation
import AppPluginHost

public enum RunnerPresentation: String, CaseIterable, Identifiable, Sendable {
    case owlOrbit, animal
    public var id: String { rawValue }
}

@MainActor
public struct RunnerSettings {
    public static let animalKey = "HappyLuluRunnerAnimal"
    public static let presentationKey = "HappyLuluRunnerPresentation"
    public static let orbitStartColorKey = "HappyLuluRunnerOrbitStartColor"
    public static let orbitEndColorKey = "HappyLuluRunnerOrbitEndColor"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var palette: PluginOrbitPalette {
        get {
            PluginOrbitPalette(startRGB: readColor(Self.orbitStartColorKey) ?? PluginOrbitPalette.standard.startRGB,
                endRGB: readColor(Self.orbitEndColorKey) ?? PluginOrbitPalette.standard.endRGB)
        }
        nonmutating set {
            let current = palette
            if current.startRGB != newValue.startRGB {
                defaults.set(String(format: "#%06X", newValue.startRGB), forKey: Self.orbitStartColorKey)
            }
            if current.endRGB != newValue.endRGB {
                defaults.set(String(format: "#%06X", newValue.endRGB), forKey: Self.orbitEndColorKey)
            }
        }
    }

    private func readColor(_ key: String) -> UInt32? {
        guard let value = defaults.string(forKey: key), value.utf8.count == 7, value.first == "#",
              value.utf8.dropFirst().allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        return UInt32(value.dropFirst(), radix: 16)
    }

    public var presentation: RunnerPresentation {
        get { defaults.string(forKey: Self.presentationKey).flatMap(RunnerPresentation.init(rawValue:)) ?? .owlOrbit }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.presentationKey) }
    }

    public var animal: RunnerAnimal {
        get { defaults.string(forKey: Self.animalKey).flatMap(RunnerAnimal.init(rawValue:)) ?? .hamster }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.animalKey) }
    }
}
