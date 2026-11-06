import Foundation
import Darwin

public enum AntigravityUsageError: LocalizedError, Equatable {
    case reportUnavailable, staleReport, futureReport, noWeeklyQuota, invalidResponse
    case cliNotFound, unsupportedVersion, timeout, commandFailed

    public var errorDescription: String? {
        switch self {
        case .reportUnavailable: return "Antigravity 사용량 JSON 파일을 선택하세요. 절대경로의 일반 파일이 필요합니다."
        case .staleReport: return "Antigravity 사용량 파일이 오래되었거나 한도가 만료되었습니다. 새 보고서를 만든 뒤 다시 조회하세요."
        case .futureReport: return "Antigravity 사용량 파일의 수정시각이 현재보다 미래입니다. 파일과 시스템 시각을 확인하세요."
        case .noWeeklyQuota: return "Antigravity 보고서에서 Gemini 주간 한도가 제공되지 않았습니다."
        case .invalidResponse: return "Antigravity 사용량 JSON을 읽지 못했습니다. 올바른 1 MiB 이하의 보고서를 선택하세요."
        case .cliNotFound: return "Antigravity CLI(agy)를 찾을 수 없습니다. 실행 파일을 선택하세요."
        case .unsupportedVersion: return "직접 조회에는 Antigravity CLI 1.1.11 이상의 정식 버전이 필요합니다."
        case .timeout: return "Antigravity 사용량 조회 시간이 초과되었습니다."
        case .commandFailed: return "Antigravity 사용량을 조회하지 못했습니다. 터미널의 agy 로그인과 연결 상태를 확인하세요."
        }
    }
}

/// Reads an exported report, or runs the read-only CLI report after explicit opt-in.
public struct AntigravityUsageProvider: UsageProvider {
    public let name = "Antigravity"
    public let executablePath: String
    public let configDirectory: String
    public let allowCLIExecution: Bool
    private let timeout: TimeInterval
    public static let maximumReportAge: TimeInterval = 900

    // configDirectory is the selected report file path for this passive provider.
    public init(executablePath: String = "", configDirectory: String = "", allowCLIExecution: Bool = false,
                timeout: TimeInterval = 25) {
        self.executablePath = executablePath
        self.configDirectory = configDirectory
        self.allowCLIExecution = allowCLIExecution
        self.timeout = timeout.isFinite ? max(0.05, min(timeout, 90)) : 25
    }

    public func makeLoginAttempt() -> (any UsageLoginAttempt)? { nil }

    public func fetch() async throws -> UsageSnapshot {
        try Task.checkCancellation()
        if allowCLIExecution {
            let request = AntigravityCommandRequest()
            do {
                return try await withTaskCancellationHandler {
                    let value: UsageSnapshot = try await withCheckedThrowingContinuation { continuation in
                        DispatchQueue.global(qos: .utility).async {
                            do { continuation.resume(returning: try fetchCLI(request)) }
                            catch { continuation.resume(throwing: error) }
                        }
                    }
                    try Task.checkCancellation()
                    return value
                } onCancel: { request.cancel() }
            } catch {
                try Task.checkCancellation()
                guard !(error is CancellationError), !configDirectory.isEmpty else { throw error }
            }
        }
        return try readReport()
    }

    private func readReport() throws -> UsageSnapshot {
        guard configDirectory.hasPrefix("/") else { throw AntigravityUsageError.reportUnavailable }
        // A bounded regular-file read avoids following links into unrelated private files or devices.
        let fd = open(configDirectory, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw AntigravityUsageError.reportUnavailable }
        defer { close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG else {
            throw AntigravityUsageError.reportUnavailable
        }
        guard before.st_size <= 1_048_576 else { throw AntigravityUsageError.invalidResponse }
        let modifiedAt = Date(timeIntervalSince1970: Double(before.st_mtimespec.tv_sec) + Double(before.st_mtimespec.tv_nsec) / 1_000_000_000)
        let now = Date()
        guard modifiedAt <= now else { throw AntigravityUsageError.futureReport }
        guard now.timeIntervalSince(modifiedAt) <= Self.maximumReportAge else { throw AntigravityUsageError.staleReport }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            try Task.checkCancellation()
            let count = read(fd, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw AntigravityUsageError.reportUnavailable
            }
            guard data.count + count <= 1_048_576 else { throw AntigravityUsageError.invalidResponse }
            data.append(contentsOf: buffer.prefix(count))
        }
        var after = stat()
        guard fstat(fd, &after) == 0, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              data.count == after.st_size else { throw AntigravityUsageError.invalidResponse }
        let parsed = try Self.parseUsageReport(data)
        guard let reset = parsed.weekly.resetDate, reset > now else { throw AntigravityUsageError.staleReport }
        try Task.checkCancellation()
        return UsageSnapshot(weekly: parsed.weekly, fetchedAt: modifiedAt)
    }

    private func fetchCLI(_ request: AntigravityCommandRequest) throws -> UsageSnapshot {
        let executable = try resolveExecutable()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("happylulu-agy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        // Opt-in can start user-configured MCP servers/hooks; a private cwd excludes project configuration.
        for name in ["open", "xdg-open", "browser"] {
            let blocker = directory.appendingPathComponent(name)
            try Data("#!/bin/sh\nexit 1\n".utf8).write(to: blocker)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocker.path)
        }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = directory.path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        environment["BROWSER"] = directory.appendingPathComponent("browser").path
        environment["PWD"] = directory.path
        environment["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true"
        let version = try request.run(executable, arguments: ["--version"], directory: directory,
                                      environment: environment, timeout: min(timeout, 3))
        // Older CLI versions could interpret unsupported slash commands as a model prompt.
        guard Self.supportsUsageReport(version) else { throw AntigravityUsageError.unsupportedVersion }
        let report = try request.run(executable, arguments: ["-p", "/usage", "--output-format", "json"],
                                     directory: directory, environment: environment, timeout: timeout)
        let value = try Self.parseUsageReport(report)
        guard let reset = value.weekly.resetDate, reset > Date() else { throw AntigravityUsageError.staleReport }
        return value
    }

    private func resolveExecutable() throws -> String {
        let fm = FileManager.default
        let custom = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let paths = custom.isEmpty
            ? ["/opt/homebrew/bin/agy", "/usr/local/bin/agy", fm.homeDirectoryForCurrentUser.path + "/.local/bin/agy"] +
                (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/agy" }
            : [(custom as NSString).expandingTildeInPath]
        for path in paths where path.hasPrefix("/") {
            var directory: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &directory), !directory.boolValue, fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        throw AntigravityUsageError.cliNotFound
    }

    private static func supportsUsageReport(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else { return false }
        let parts = text.split(separator: ".").compactMap { UInt($0) }
        return parts.count == 3 && !parts.lexicographicallyPrecedes([1, 1, 11])
    }

    static func parseUsageReport(_ data: Data) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let report = try? decoder.decode(AntigravityReport.self, from: data),
              report.status == "SUCCESS", report.command.name == "usage" else {
            throw AntigravityUsageError.invalidResponse
        }
        let buckets = report.command.data.groups.flatMap(\.buckets).filter {
            ($0.bucketId ?? $0.id) == "gemini-weekly" && $0.disabled != true
        }
        guard !buckets.isEmpty else { throw AntigravityUsageError.noWeeklyQuota }
        guard buckets.count == 1, let bucket = buckets.first,
              let remaining = bucket.remainingFraction ?? bucket.remaining?.remainingFraction,
              remaining.isFinite, (0...1).contains(remaining),
              let resetText = bucket.resetTime, let reset = parseDate(resetText) else {
            throw AntigravityUsageError.invalidResponse
        }
        // The CLI report has no verified account identity; never persist an attributed history.
        return UsageSnapshot(weekly: UsageWindow(usedPercent: (1 - remaining) * 100,
            windowDurationMins: 10_080, resetsAt: reset.timeIntervalSince1970))
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

private struct AntigravityReport: Decodable {
    let status: String
    let command: Command
    struct Command: Decodable { let name: String; let data: Payload }
    struct Payload: Decodable { let groups: [Group] }
    struct Group: Decodable { let buckets: [Bucket] }
    struct Bucket: Decodable {
        let bucketId: String?
        let id: String?
        let disabled: Bool?
        let remainingFraction: Double?
        let remaining: Remaining?
        let resetTime: String?
    }
    struct Remaining: Decodable {
        let remainingFraction: Double?
        private enum CodingKeys: String, CodingKey { case remainingFraction, kind = "case", value }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            if let value = try values.decodeIfPresent(Double.self, forKey: .remainingFraction) { remainingFraction = value }
            else if try values.decodeIfPresent(String.self, forKey: .kind) == "remainingFraction" {
                remainingFraction = try values.decodeIfPresent(Double.self, forKey: .value)
            } else { remainingFraction = nil }
        }
    }
}

private final class AntigravityCommandRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var processGroup: pid_t?

    func cancel() {
        lock.lock(); cancelled = true
        if let processGroup { kill(-processGroup, SIGKILL) }
        lock.unlock()
    }

    private func checkCancellation() throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
    }

    func run(_ executable: String, arguments: [String], directory: URL,
             environment: [String: String], timeout: TimeInterval) throws -> Data {
        try checkCancellation()
        var descriptors: [Int32] = [0, 0]
        guard pipe(&descriptors) == 0 else { throw AntigravityUsageError.commandFailed }
        defer { close(descriptors[0]); close(descriptors[1]) }
        var actions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw AntigravityUsageError.commandFailed }
        defer { posix_spawn_file_actions_destroy(&actions) }
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else { throw AntigravityUsageError.commandFailed }
        defer { posix_spawnattr_destroy(&attributes) }
        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        for number in [SIGINT, SIGTERM, SIGHUP] { sigaddset(&defaultSignals, number) }
        var mask = sigset_t()
        sigemptyset(&mask)
        guard posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDOUT_FILENO) == 0,
              posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0) == 0,
              posix_spawn_file_actions_addclose(&actions, descriptors[0]) == 0,
              posix_spawn_file_actions_addclose(&actions, descriptors[1]) == 0,
              posix_spawn_file_actions_addchdir_np(&actions, directory.path) == 0,
              posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT |
                  POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0,
              posix_spawnattr_setsigdefault(&attributes, &defaultSignals) == 0,
              posix_spawnattr_setsigmask(&attributes, &mask) == 0 else { throw AntigravityUsageError.commandFailed }
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var pid: pid_t = 0
        guard posix_spawn(&pid, executable, &actions, &attributes, argv, envp) == 0 else {
            throw AntigravityUsageError.commandFailed
        }
        lock.lock(); processGroup = pid
        if cancelled { kill(-pid, SIGKILL) }
        lock.unlock()
        defer {
            // Keep the root unreaped until group cleanup, preventing process-group ID reuse.
            // shortcut: detached MCP can escape this group, add stronger containment when CLI isolation is supported.
            lock.lock(); kill(-pid, SIGKILL); processGroup = nil; lock.unlock()
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        }
        close(descriptors[1]); descriptors[1] = -1
        guard fcntl(descriptors[0], F_SETFL, O_NONBLOCK) != -1 else { throw AntigravityUsageError.commandFailed }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var output = Data()
        var bytes = [UInt8](repeating: 0, count: 8192)
        func drain() throws {
            while true {
                let count = read(descriptors[0], &bytes, bytes.count)
                if count <= 0 { break }
                guard output.count + count <= 1_048_576 else { throw AntigravityUsageError.invalidResponse }
                output.append(contentsOf: bytes.prefix(count))
            }
        }
        while true {
            try checkCancellation()
            try drain()
            var info = siginfo_t()
            guard waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT) == 0 else {
                throw AntigravityUsageError.commandFailed
            }
            if info.si_pid == pid {
                guard info.si_code == CLD_EXITED && info.si_status == 0 else { throw AntigravityUsageError.commandFailed }
                try drain()
                return output
            }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw AntigravityUsageError.timeout }
            // Wait for output readiness; fixed sleeps throttle small pipe writes under backpressure.
            var descriptor = pollfd(fd: descriptors[0], events: Int16(POLLIN), revents: 0)
            let result = poll(&descriptor, 1, Int32(max(1, min(50, ceil(remaining * 1000)))))
            if result < 0, errno != EINTR { throw AntigravityUsageError.commandFailed }
            if descriptor.revents & Int16(POLLHUP | POLLERR) != 0 { usleep(1_000) }
        }
    }
}
