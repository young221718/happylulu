import Foundation

/// Providers own usage/authentication transport. UI and history consume normalized snapshots.
public protocol UsageProvider: Sendable {
    var name: String { get }
    func fetch() async throws -> UsageSnapshot
    func makeLoginAttempt() -> (any UsageLoginAttempt)?
}

public protocol UsageLoginAttempt: AnyObject, Sendable {
    func login(openBrowser: @escaping @Sendable (URL) -> Void) async throws
    func cancel()
}

public struct CodexUsageProvider: UsageProvider {
    public let name = "Codex"
    public let executablePath: String
    public let configDirectory: String
    public init(executablePath: String = "", configDirectory: String = "") {
        self.executablePath = executablePath; self.configDirectory = configDirectory
    }
    public func fetch() async throws -> UsageSnapshot { try await CodexClient().fetch(customPath: executablePath, configDirectory: configDirectory) }
    public func makeLoginAttempt() -> (any UsageLoginAttempt)? { CodexProviderLogin(path: executablePath, configDirectory: configDirectory) }
}

private final class CodexProviderLogin: UsageLoginAttempt, @unchecked Sendable {
    let path: String
    let configDirectory: String
    let attempt = CodexLoginAttempt()
    init(path: String, configDirectory: String) { self.path = path; self.configDirectory = configDirectory }
    func cancel() { attempt.cancel() }
    func login(openBrowser: @escaping @Sendable (URL) -> Void) async throws {
        try await withTaskCancellationHandler {
            try await attempt.login(customPath: path, configDirectory: configDirectory, openBrowser: openBrowser)
        } onCancel: { self.cancel() }
    }
}

/// Retains unsupported saved profiles without reading or running their former provider.
public struct UnavailableUsageProvider: UsageProvider {
    public let name = "지원하지 않는 연결"
    public init() {}
    public func fetch() async throws -> UsageSnapshot { throw UsageError.unsupportedProvider }
    public func makeLoginAttempt() -> (any UsageLoginAttempt)? { nil }
}
