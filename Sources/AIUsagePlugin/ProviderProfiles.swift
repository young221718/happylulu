import Foundation

public struct UsageProviderDescriptor: Sendable, Identifiable {
    public enum Connection: Sendable { case codex, statusLine }
    public let id: String
    public let name: String
    public let connection: Connection
    public let makeProvider: @Sendable (UsageProfile) -> any UsageProvider

    public init(id: String, name: String, connection: Connection,
                makeProvider: @escaping @Sendable (UsageProfile) -> any UsageProvider) {
        self.id = id; self.name = name; self.connection = connection; self.makeProvider = makeProvider
    }
}

/// Add a descriptor and adapter together; unknown saved providers never fall back to Codex.
public struct UsageProviderRegistry: Sendable {
    public let providers: [UsageProviderDescriptor]
    public init(providers: [UsageProviderDescriptor]) { self.providers = providers }
    public func descriptor(for id: String) -> UsageProviderDescriptor? { providers.first { $0.id == id } }
    public static let standard = UsageProviderRegistry(providers: [
        UsageProviderDescriptor(id: "codex", name: "Codex", connection: .codex) {
            CodexUsageProvider(executablePath: $0.preferences.cliPath, configDirectory: $0.preferences.configDirectory)
        },
        UsageProviderDescriptor(id: "claude", name: "Claude", connection: .statusLine) {
            StatusLineUsageProvider(providerID: "claude", name: "Claude", reportPath: $0.reportPath)
        },
        UsageProviderDescriptor(id: "antigravity", name: "Antigravity", connection: .statusLine) {
            StatusLineUsageProvider(providerID: "antigravity", name: "Antigravity", reportPath: $0.reportPath)
        }
    ])
}

public struct UsageProfile: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let providerID: String
    public var name: String
    public var preferences: Preferences
    public var reportPath: String

    public init(providerID: String, name: String, preferences: Preferences = Preferences(), reportPath: String = "") {
        id = UUID().uuidString; self.providerID = providerID; self.name = name
        self.preferences = preferences; self.reportPath = reportPath
    }

    private enum CodingKeys: String, CodingKey { case id, providerID, name, preferences, reportPath }
    private enum PreferenceKeys: String, CodingKey, CaseIterable {
        case refreshMinutes, labelFormat, notificationsEnabled, notificationThreshold, cliPath, configDirectory
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        providerID = try values.decode(String.self, forKey: .providerID)
        name = try values.decode(String.self, forKey: .name)
        reportPath = try values.decode(String.self, forKey: .reportPath)
        let fields = try values.nestedContainer(keyedBy: PreferenceKeys.self, forKey: .preferences)
        for key in PreferenceKeys.allCases {
            guard fields.contains(key), try !fields.decodeNil(forKey: key) else { throw CocoaError(.coderReadCorrupt) }
        }
        preferences = try values.decode(Preferences.self, forKey: .preferences)
        guard UUID(uuidString: id) != nil, !providerID.isEmpty, !name.isEmpty, name.count <= 100,
              reportPath.isEmpty || reportPath.hasPrefix("/"),
              preferences.configDirectory.isEmpty || preferences.configDirectory.hasPrefix("/"),
              preferences.cliPath.isEmpty || preferences.cliPath.hasPrefix("/") else { throw CocoaError(.coderReadCorrupt) }
        preferences.normalize()
    }
}

public struct UsageProfileSettings: Codable, Sendable {
    public static let key = "HappyLuluAIUsage.providers.v2"
    public var profiles: [UsageProfile] = []
    public var selectedID: String?
    public private(set) var readOnly = false
    private let schema = 2
    private enum CodingKeys: String, CodingKey { case schema, profiles, selectedID }
    public init() {}
    public var selected: UsageProfile? { profiles.first { $0.id == selectedID } }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(Int.self, forKey: .schema) == 2, values.contains(.selectedID) else {
            throw CocoaError(.coderReadCorrupt)
        }
        profiles = try values.decode([UsageProfile].self, forKey: .profiles)
        selectedID = try values.decodeIfPresent(String.self, forKey: .selectedID)
        guard profiles.count <= 32, Set(profiles.map(\.id)).count == profiles.count,
              selectedID == nil || profiles.contains(where: { $0.id == selectedID }) else { throw CocoaError(.coderReadCorrupt) }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schema, forKey: .schema)
        try values.encode(profiles, forKey: .profiles)
        try values.encode(selectedID, forKey: .selectedID)
    }

    public static func load(from defaults: UserDefaults, registry: UsageProviderRegistry = .standard) -> Self {
        guard defaults.object(forKey: key) != nil else { return Self() }
        guard let data = defaults.data(forKey: key), var settings = try? JSONDecoder().decode(Self.self, from: data),
              settings.profiles.allSatisfy({ registry.descriptor(for: $0.providerID) != nil }) else {
            var blocked = Self(); blocked.readOnly = true; return blocked
        }
        settings.readOnly = false
        return settings
    }

    public func save(to defaults: UserDefaults) throws {
        guard !readOnly else { throw CocoaError(.fileWriteNoPermission) }
        // Validate before writing, including caller-created paths and selection invariants.
        let data = try JSONEncoder().encode(self)
        _ = try JSONDecoder().decode(Self.self, from: data)
        defaults.set(data, forKey: Self.key)
    }
}
