import Foundation

enum KeepAwakeMode: String, CaseIterable {
    case displayAndSystem, system
}

enum KeepAwakeDuration: Int, CaseIterable {
    case indefinite = 0, minutes15 = 900, minutes30 = 1800, hour = 3600, twoHours = 7200
    var seconds: TimeInterval? { self == .indefinite ? nil : TimeInterval(rawValue) }
}

@MainActor
struct KeepAwakeSettings {
    static let modeKey = "macUtilities.keepAwake.mode"
    static let durationKey = "macUtilities.keepAwake.duration"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var mode: KeepAwakeMode {
        get { defaults.string(forKey: Self.modeKey).flatMap(KeepAwakeMode.init(rawValue:)) ?? .displayAndSystem }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.modeKey) }
    }
    var duration: KeepAwakeDuration {
        get { KeepAwakeDuration(rawValue: defaults.integer(forKey: Self.durationKey)) ?? .indefinite }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.durationKey) }
    }
}
