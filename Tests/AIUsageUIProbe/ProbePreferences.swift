import Foundation

/// Synthetic controls share no persistent preferences with the fixed development identity.
final class ProbePreferences: UserDefaults, @unchecked Sendable {
    static let shared = ProbePreferences(suiteName: nil)!
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    override func object(forKey key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    override func set(_ value: Any?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }

    override func set(_ value: Bool, forKey key: String) { set(value as Any, forKey: key) }
    override func string(forKey key: String) -> String? { object(forKey: key) as? String }
    override func data(forKey key: String) -> Data? { object(forKey: key) as? Data }
    override func bool(forKey key: String) -> Bool { object(forKey: key) as? Bool ?? false }
    override func removeObject(forKey key: String) { set(nil, forKey: key) }
}
