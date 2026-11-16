import Foundation

/// The published Codex feature must never rewrite the development build's account profiles.
public enum ReleasedUsagePreferences {
    public static let key = "HappyLuluAIUsage.codex-release.preferences.v1"

    public struct State: Codable, Sendable {
        public var preferences: Preferences
        public var requiresConnection: Bool
        public var readOnly = false
        private var schema = 1

        private enum CodingKeys: String, CodingKey { case schema, preferences, requiresConnection }
        private enum PreferenceKeys: String, CodingKey, CaseIterable {
            case refreshMinutes, labelFormat, notificationsEnabled, notificationThreshold, cliPath, configDirectory
        }
        public init(preferences: Preferences = Preferences(), requiresConnection: Bool = false, readOnly: Bool = false) {
            self.preferences = preferences; self.requiresConnection = requiresConnection; self.readOnly = readOnly
        }
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            guard try values.decode(Int.self, forKey: .schema) == 1 else { throw CocoaError(.coderReadCorrupt) }
            let fields = try values.nestedContainer(keyedBy: PreferenceKeys.self, forKey: .preferences)
            for key in PreferenceKeys.allCases {
                guard fields.contains(key), try !fields.decodeNil(forKey: key) else { throw CocoaError(.coderReadCorrupt) }
            }
            preferences = try values.decode(Preferences.self, forKey: .preferences)
            requiresConnection = try values.decode(Bool.self, forKey: .requiresConnection)
            guard preferences.configDirectory.isEmpty || preferences.configDirectory.hasPrefix("/") else {
                throw CocoaError(.coderReadCorrupt)
            }
            preferences.normalize()
        }
    }

    public static func load(from defaults: UserDefaults) -> State {
        if defaults.object(forKey: key) != nil {
            guard let data = defaults.data(forKey: key),
                  let state = try? JSONDecoder().decode(State.self, from: data) else {
                return State(requiresConnection: true, readOnly: true)
            }
            return state
        }
        let oldKey = "HappyLuluAIUsage.preferences.v1"
        guard defaults.object(forKey: oldKey) != nil else { return State() }
        guard let data = defaults.data(forKey: oldKey),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var preferences = try? JSONDecoder().decode(Preferences.self, from: data) else {
            return State(requiresConnection: true)
        }
        if object["profiles"] != nil {
            guard let profiles = object["profiles"] as? [[String: Any]],
                  let selected = object["selectedProfileID"] as? String,
                  profiles.filter({ $0["id"] as? String == selected }).count == 1,
                  let profile = profiles.first(where: { $0["id"] as? String == selected }),
                  profile["provider"] as? String == "codex",
                  let path = profile["cliPath"] as? String,
                  let directory = profile["configDirectory"] as? String,
                  directory.isEmpty || directory.hasPrefix("/") else {
                return State(requiresConnection: true)
            }
            preferences.cliPath = path
            preferences.configDirectory = directory
        } else {
            let legacyKeys = ["refreshMinutes", "labelFormat", "notificationsEnabled", "notificationThreshold", "cliPath"]
            guard object["selectedProfileID"] == nil,
                  legacyKeys.allSatisfy({ object[$0] != nil && !(object[$0] is NSNull) }) else {
                return State(requiresConnection: true)
            }
        }
        preferences.normalize()
        guard preferences.configDirectory.isEmpty || preferences.configDirectory.hasPrefix("/") else {
            return State(requiresConnection: true)
        }
        return State(preferences: preferences)
    }

    public static func save(_ state: State, to defaults: UserDefaults) throws {
        guard !state.readOnly, !load(from: defaults).readOnly else { throw CocoaError(.fileWriteNoPermission) }
        let data = try JSONEncoder().encode(state)
        _ = try JSONDecoder().decode(State.self, from: data)
        defaults.set(data, forKey: key)
    }
}
