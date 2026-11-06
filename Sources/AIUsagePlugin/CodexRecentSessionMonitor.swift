import Foundation
import Darwin

public enum CodexRecentSessionMonitorError: Error, Equatable, Sendable {
    case invalidPath, unsafeDirectory, unavailable, discoveryLimitExceeded
}

public struct CodexRecentSessionObservation: Equatable, Sendable {
    public let latestSample: TokenSpeedSample?
    public let discoveredSessionCount: Int
    public let unsupportedSessionCount: Int
    public let isCatchingUp: Bool

    public init(latestSample: TokenSpeedSample?, discoveredSessionCount: Int,
                unsupportedSessionCount: Int, isCatchingUp: Bool) {
        self.latestSample = latestSample
        self.discoveredSessionCount = discoveredSessionCount
        self.unsupportedSessionCount = unsupportedSessionCount
        self.isCatchingUp = isCatchingUp
    }
}

public protocol CodexRecentSessionMonitoring: Sendable {
    var scopeKey: String { get }
    func poll(now: Date) async throws -> CodexRecentSessionObservation
}

/// Observes recent local rollouts from one chosen Codex home. This scope is not a signed-in account.
public actor CodexRecentSessionMonitor: CodexRecentSessionMonitoring {
    public nonisolated let scopeKey = "codex-recent:" + UUID().uuidString
    private let codexHome: String
    private var watched: [String: Watched] = [:]
    private var nextPoll = 0
    private static let maximumSessions = 8
    private static let maximumPolls = 4 // At most 4 MiB of incremental body bytes per poll.
    private static let maximumDirectoryEntries = 16_384
    private static let directoryFlags = O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK

    public init(codexHome: String) throws {
        let parts = codexHome.split(separator: "/", omittingEmptySubsequences: false)
        guard codexHome.hasPrefix("/"), !codexHome.utf8.contains(0),
              codexHome != "/", !parts.contains("."), !parts.contains("..") else {
            throw CodexRecentSessionMonitorError.invalidPath
        }
        self.codexHome = codexHome.hasSuffix("/") ? String(codexHome.dropLast()) : codexHome
    }

    public func poll(now: Date = Date()) async throws -> CodexRecentSessionObservation {
        try Task.checkCancellation()
        guard now.timeIntervalSince1970.isFinite else { throw CodexRecentSessionMonitorError.unavailable }
        let candidates = try discover(now: now)
        let paths = Set(candidates.map(\.path))
        watched = watched.filter { paths.contains($0.key) }
        for candidate in candidates where watched[candidate.path] == nil {
            watched[candidate.path] = Watched(reader: try CodexSessionTokenSpeedReader(path: candidate.path))
        }
        if !candidates.isEmpty {
            let start = nextPoll % candidates.count
            let count = min(Self.maximumPolls, candidates.count)
            for step in 0..<count {
                try Task.checkCancellation()
                let path = candidates[(start + step) % candidates.count].path
                guard var state = watched[path] else { continue }
                let previousScope = state.reader.scopeKey
                do {
                    let samples = try state.reader.poll(now: now)
                    if previousScope != state.reader.scopeKey { state.latest = nil }
                    let invalidated = state.reader.invalidatedRequestKeys
                    if let previous = state.latest, invalidated.contains(previous.requestKey) { state.latest = nil }
                    if let latest = samples.filter({ !invalidated.contains($0.requestKey) }).max(by: { $0.recordedAt < $1.recordedAt }) {
                        if state.latest == nil || latest.recordedAt >= state.latest!.recordedAt { state.latest = latest }
                    }
                    state.unsupported = false; state.wasPolled = true
                } catch is CancellationError { throw CancellationError() }
                catch {
                    // A malformed or unsupported rollout must not hide healthy sessions.
                    state.latest = nil; state.unsupported = true; state.wasPolled = true
                }
                watched[path] = state
            }
            nextPoll = (start + count) % candidates.count
        } else { nextPoll = 0 }
        let latest = watched.values.compactMap(\.latest).filter {
            $0.recordedAt <= now && now.timeIntervalSince($0.recordedAt) <= TokenSpeed.maximumAge
        }.max { $0.recordedAt < $1.recordedAt }
        let sample = latest.flatMap {
            TokenSpeedSample(outputTokens: $0.outputTokens, durationMilliseconds: $0.durationMilliseconds,
                recordedAt: $0.recordedAt, accountKey: scopeKey, requestKey: $0.requestKey)
        }
        return CodexRecentSessionObservation(latestSample: sample, discoveredSessionCount: candidates.count,
            unsupportedSessionCount: watched.values.filter(\.unsupported).count,
            isCatchingUp: watched.values.contains { !$0.wasPolled || (!$0.unsupported && $0.reader.hasMoreData) })
    }

    private struct Watched {
        var reader: CodexSessionTokenSpeedReader
        var latest: TokenSpeedSample?
        var unsupported = false
        var wasPolled = false
    }
    private struct Candidate { let path: String; let modified: Date }

    private func discover(now: Date) throws -> [Candidate] {
        let home = try Self.openRoot(codexHome)
        defer { close(home) }
        guard let sessions = Self.openChild(home, name: "sessions") else { return [] }
        defer { close(sessions) }
        var candidates: [Candidate] = []
        var entryCount = 0
        for day in Self.recentDays(now: now) {
            try Task.checkCancellation()
            let parts = day.split(separator: "/").map(String.init)
            guard let year = Self.openChild(sessions, name: parts[0]) else { continue }
            defer { close(year) }
            guard let month = Self.openChild(year, name: parts[1]) else { continue }
            defer { close(month) }
            guard let date = Self.openChild(month, name: parts[2]) else { continue }
            defer { close(date) }
            let duplicate = dup(date)
            guard duplicate >= 0 else { throw CodexRecentSessionMonitorError.unavailable }
            guard let directory = fdopendir(duplicate) else {
                close(duplicate); throw CodexRecentSessionMonitorError.unavailable
            }
            defer { closedir(directory) }
            while let entry = readdir(directory) {
                entryCount += 1
                guard entryCount <= Self.maximumDirectoryEntries else {
                    throw CodexRecentSessionMonitorError.discoveryLimitExceeded
                }
                let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                guard Self.isRollout(name, day: day) else { continue }
                var value = stat()
                guard fstatat(date, name, &value, AT_SYMLINK_NOFOLLOW) == 0,
                      value.st_mode & S_IFMT == S_IFREG, value.st_uid == getuid(), value.st_size >= 0 else { continue }
                let modified = Date(timeIntervalSince1970: Double(value.st_mtimespec.tv_sec) + Double(value.st_mtimespec.tv_nsec) / 1_000_000_000)
                guard modified <= now, now.timeIntervalSince(modified) <= TokenSpeed.maximumAge else { continue }
                candidates.append(Candidate(path: codexHome + "/sessions/" + day + "/" + name, modified: modified))
            }
        }
        return candidates.sorted {
            $0.modified == $1.modified ? $0.path < $1.path : $0.modified > $1.modified
        }.prefix(Self.maximumSessions).map { $0 }
    }

    private static func openRoot(_ path: String) throws -> Int32 {
        var descriptor = open("/", directoryFlags)
        guard descriptor >= 0 else { throw CodexRecentSessionMonitorError.unavailable }
        for part in path.split(separator: "/") {
            let next = openat(descriptor, String(part), directoryFlags)
            let failure = errno
            close(descriptor)
            guard next >= 0 else {
                throw failure == ENOENT ? CodexRecentSessionMonitorError.unavailable : .unsafeDirectory
            }
            descriptor = next
        }
        var value = stat()
        guard fstat(descriptor, &value) == 0, value.st_mode & S_IFMT == S_IFDIR, value.st_uid == getuid() else {
            close(descriptor); throw CodexRecentSessionMonitorError.unsafeDirectory
        }
        return descriptor
    }

    private static func openChild(_ parent: Int32, name: String) -> Int32? {
        let descriptor = openat(parent, name, directoryFlags)
        guard descriptor >= 0 else { return nil }
        var value = stat()
        guard fstat(descriptor, &value) == 0, value.st_mode & S_IFMT == S_IFDIR, value.st_uid == getuid() else {
            close(descriptor); return nil
        }
        return descriptor
    }

    private static func recentDays(now: Date) -> [String] {
        var result = Set<String>()
        for zone in [TimeZone(secondsFromGMT: 0)!, .current] {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            for age in 0..<30 {
                guard let date = calendar.date(byAdding: .day, value: -age, to: now) else { continue }
                let parts = calendar.dateComponents([.year, .month, .day], from: date)
                if let year = parts.year, let month = parts.month, let day = parts.day {
                    result.insert(String(format: "%04d/%02d/%02d", year, month, day))
                }
            }
        }
        return result.sorted(by: >)
    }

    private static func isRollout(_ name: String, day: String) -> Bool {
        let date = day.replacingOccurrences(of: "/", with: "-")
        let prefix = "rollout-" + date + "T"
        guard name.hasPrefix(prefix), name.hasSuffix(".jsonl"), name.utf8.count == prefix.utf8.count + 8 + 1 + 36 + 6 else { return false }
        let tail = name.dropFirst(prefix.count)
        let time = tail.prefix(8)
        guard time.range(of: #"^\d{2}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let components = time.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3, components[0] < 24, components[1] < 60, components[2] < 60,
              tail.dropFirst(8).first == "-" else { return false }
        return UUID(uuidString: String(tail.dropFirst(9).dropLast(6))) != nil
    }
}
