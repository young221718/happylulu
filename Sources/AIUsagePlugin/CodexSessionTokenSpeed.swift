import Foundation
import CryptoKit
import Darwin

public enum CodexSessionTokenSpeedError: Error, Equatable, Sendable {
    case invalidPath, unsafeFile, fileTooLarge, changedFile, invalidData, unsupportedSession
}

public enum CodexSessionTokenSpeedMetricKind: String, Sendable {
    /// Native assistant-message token count and that message's recorded duration.
    /// Turn averages include reasoning, tools, approval and wait time; they are not decoder speed.
    case message, completedTurn, inProgressTurn
}

/// Reads only a user-selected rollout. Samples identify the selected file, never a ChatGPT account.
public struct CodexSessionTokenSpeedReader: Sendable {
    public private(set) var scopeKey: String
    public private(set) var hasMoreData = false
    /// Remove matching cached samples after each poll, including when that poll returns no new samples.
    public private(set) var invalidatedRequestKeys: Set<String> = []
    private let path: String
    private var identity: Identity?
    private var offset: Int64 = 0
    private var prefixCount = 0
    private var prefixHash: String?
    private var pending = Data()
    private var discardingLine = false
    private var stream: Stream
    private static let maximumFileBytes: Int64 = 67_108_864
    private static let maximumReadBytes = 1_048_576
    private static let maximumLineBytes = 1_048_576

    public init(path: String) throws {
        guard path.hasPrefix("/"), !path.utf8.contains(0),
              !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw CodexSessionTokenSpeedError.invalidPath
        }
        self.path = path
        let scope = "codex-session:" + UUID().uuidString
        scopeKey = scope; stream = Stream(scopeKey: scope)
    }

    public static func metricKind(for sample: TokenSpeedSample) -> CodexSessionTokenSpeedMetricKind? {
        if sample.requestKey.hasPrefix("message:") { return .message }
        if sample.requestKey.hasPrefix("turn:") { return .completedTurn }
        if sample.requestKey.hasPrefix("turn-progress:") { return .inProgressTurn }
        return nil
    }

    /// At most 1 MiB is read per call. Call again while hasMoreData, then poll for future appends.
    public mutating func poll(now: Date = Date()) throws -> [TokenSpeedSample] {
        invalidatedRequestKeys = []
        try Task.checkCancellation()
        let descriptor = try openSelectedFile()
        defer { close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_uid == getuid(), before.st_size >= 0 else { throw CodexSessionTokenSpeedError.unsafeFile }
        guard before.st_size <= Self.maximumFileBytes else { throw CodexSessionTokenSpeedError.fileTooLarge }
        let current = Identity(before)
        if let old = identity,
           old.device != current.device || old.inode != current.inode || before.st_size < offset ||
            (old.size == current.size && old.modified != current.modified) {
            reset()
        }
        if prefixCount > 0 {
            let prefix = try read(descriptor, offset: 0, count: prefixCount)
            if prefix.count != prefixCount || Self.fingerprint(prefix) != prefixHash { reset() }
        }
        if prefixCount == 0, before.st_size > 0 {
            prefixCount = min(4096, Int(before.st_size))
            prefixHash = Self.fingerprint(try read(descriptor, offset: 0, count: prefixCount))
        }
        let count = Int(min(Int64(Self.maximumReadBytes), before.st_size - offset))
        let bytes = try read(descriptor, offset: offset, count: count)
        let selectedDescriptor = try openSelectedFile()
        defer { close(selectedDescriptor) }
        var after = stat(), selected = stat()
        guard fstat(descriptor, &after) == 0, fstat(selectedDescriptor, &selected) == 0,
              selected.st_mode & S_IFMT == S_IFREG, selected.st_dev == after.st_dev, selected.st_ino == after.st_ino,
              after.st_size >= before.st_size, after.st_size <= Self.maximumFileBytes,
              bytes.count == count else { reset(); throw CodexSessionTokenSpeedError.changedFile }
        if prefixCount > 0 {
            guard Self.fingerprint(try read(descriptor, offset: 0, count: prefixCount)) == prefixHash else {
                reset(); throw CodexSessionTokenSpeedError.changedFile
            }
        }
        offset += Int64(bytes.count)
        identity = Identity(after)
        hasMoreData = after.st_size > offset
        do {
            var result: [TokenSpeedSample] = []
            for byte in bytes {
                if byte == 0x0A {
                    if !discardingLine, !pending.isEmpty {
                        if pending.last == 0x0D { pending.removeLast() }
                        if let sample = try stream.consume(pending, now: now) { result.append(sample) }
                    }
                    pending.removeAll(keepingCapacity: true); discardingLine = false
                } else if !discardingLine {
                    if pending.count < Self.maximumLineBytes { pending.append(byte) }
                    else { pending.removeAll(keepingCapacity: true); discardingLine = true }
                }
            }
            if !hasMoreData { result.append(contentsOf: try stream.flush(now: now)) }
            invalidatedRequestKeys = stream.invalidatedRequestKeys
            stream.invalidatedRequestKeys = []
            return result
        } catch {
            reset()
            throw error
        }
    }

    // Walk every component through held directory descriptors; a replaced parent cannot redirect a read.
    private func openSelectedFile() throws -> Int32 {
        let parts = path.split(separator: "/")
        guard let leaf = parts.last else { throw CodexSessionTokenSpeedError.unsafeFile }
        var directory = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directory >= 0 else { throw CodexSessionTokenSpeedError.unsafeFile }
        defer { close(directory) }
        for part in parts.dropLast() {
            let next = openat(directory, String(part), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            guard next >= 0 else { throw CodexSessionTokenSpeedError.unsafeFile }
            close(directory); directory = next
        }
        let descriptor = openat(directory, String(leaf), O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw CodexSessionTokenSpeedError.unsafeFile }
        return descriptor
    }

    private mutating func reset() {
        scopeKey = "codex-session:" + UUID().uuidString
        stream = Stream(scopeKey: scopeKey)
        identity = nil; offset = 0; prefixCount = 0; prefixHash = nil
        pending.removeAll(keepingCapacity: false); discardingLine = false; hasMoreData = false
        invalidatedRequestKeys = []
    }

    private func read(_ descriptor: Int32, offset: Int64, count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        var bytes = [UInt8](repeating: 0, count: count)
        let received = bytes.withUnsafeMutableBytes { Darwin.pread(descriptor, $0.baseAddress, count, off_t(offset)) }
        guard received >= 0 else { throw CodexSessionTokenSpeedError.unsafeFile }
        return Data(bytes.prefix(received))
    }
    private static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private struct Identity: Sendable {
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modified: String
        init(_ value: stat) {
            device = value.st_dev; inode = value.st_ino; size = value.st_size
            modified = "\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec)"
        }
    }

    private struct Stream: Sendable {
        let scopeKey: String
        var session: UUID?
        var seen: [String: Metrics] = [:]
        var turns: [String: Turn] = [:]
        var responseCount = 0
        var invalidatedRequestKeys: Set<String> = []

        mutating func consume(_ line: Data, now: Date) throws -> TokenSpeedSample? {
            guard let record = try? JSONDecoder().decode(Record.self, from: line) else {
                throw CodexSessionTokenSpeedError.invalidData
            }
            if record.type == "session_meta" {
                guard let meta = record.meta, let id = UUID(uuidString: meta.id) else {
                    throw CodexSessionTokenSpeedError.invalidData
                }
                if let session, session != id { throw CodexSessionTokenSpeedError.invalidData }
                session = id
                return nil
            }
            guard let session else { throw CodexSessionTokenSpeedError.invalidData }
            if let event = record.event, event.type == "turn_aborted" {
                if let id = event.turnID, Self.validID(id) {
                    var turn = try turnState(id)
                    turn.terminal = true; turn.aborted = true
                    turns[id] = turn
                    invalidate(id, session: session, completed: true)
                } else if event.turnID == nil {
                    // Older abort events omit the ID. Only active progress can safely be invalidated.
                    for id in turns.keys where turns[id]?.terminal == false {
                        turns[id]?.terminal = true; turns[id]?.aborted = true
                        invalidate(id, session: session, completed: false)
                    }
                }
                return nil
            }
            if let usage = record.usage {
                guard UUID(uuidString: usage.threadID) == session else { throw CodexSessionTokenSpeedError.invalidData }
                guard Self.validID(usage.turnID), Self.validID(usage.responseID),
                      let count = usage.tokens, (0...100_000_000).contains(count),
                      let date = record.date, Self.recent(date, now: now) else { return nil }
                var turn = try turnState(usage.turnID)
                let observation = Observation(tokens: count, date: date)
                if let old = turn.responses[usage.responseID] {
                    guard old == observation else { throw CodexSessionTokenSpeedError.invalidData }
                    return nil
                }
                for old in turn.responses.values {
                    guard !(old.date < date && old.tokens > count), !(old.date > date && old.tokens < count) else {
                        throw CodexSessionTokenSpeedError.invalidData
                    }
                }
                guard responseCount < 4096 else { throw CodexSessionTokenSpeedError.invalidData }
                turn.responses[usage.responseID] = observation
                if turn.latest == nil || date > turn.latest!.date || (date == turn.latest!.date && count > turn.latest!.tokens) {
                    turn.latest = observation
                }
                responseCount += 1
                turns[usage.turnID] = turn
                return nil
            }
            if let event = record.event, event.type == "task_started" || event.type == "task_complete" {
                guard let id = event.turnID, Self.validID(id) else { return nil }
                var turn = try turnState(id)
                if event.type == "task_complete" {
                    turn.terminal = true
                    if event.failed { turn.aborted = true }
                    turns[id] = turn
                    invalidate(id, session: session, completed: event.failed)
                }
                guard let date = record.date, date <= now,
                      now.timeIntervalSince(date) <= 3600 + TokenSpeed.maximumAge else { return nil }
                if event.type == "task_started" {
                    if let start = turn.started, start != date { throw CodexSessionTokenSpeedError.invalidData }
                    turn.started = date
                } else {
                    let completion = Completion(date: date, duration: event.duration, failed: event.failed)
                    if let old = turn.completion, old != completion { throw CodexSessionTokenSpeedError.invalidData }
                    turn.completion = completion
                }
                turns[id] = turn
                return nil
            }
            guard let event = record.event, event.type == "item_completed", event.item?.type == "AgentMessage" else { return nil }
            guard let thread = event.threadID, UUID(uuidString: thread) == session else {
                throw CodexSessionTokenSpeedError.invalidData
            }
            guard let turn = event.turnID, !turn.isEmpty, turn.utf8.count <= 128,
                  let item = event.item?.id, !item.isEmpty, item.utf8.count <= 128,
                  let tokens = event.tokens, (0...100_000_000).contains(tokens),
                  let start = event.start, let end = event.end, start > 0, end > start,
                  end - start <= 3_600_000 else { return nil }
            let date = Date(timeIntervalSince1970: Double(end) / 1000)
            guard date <= now, now.timeIntervalSince(date) <= TokenSpeed.maximumAge else { return nil }
            let key = CodexSessionTokenSpeedReader.fingerprint(Data("\(session.uuidString)|\(turn)|\(item)".utf8))
            let metrics = Metrics(tokens: tokens, start: start, end: end)
            if let previous = seen[key] {
                guard previous == metrics else { throw CodexSessionTokenSpeedError.invalidData }
                return nil
            }
            guard seen.count < 4096 else { throw CodexSessionTokenSpeedError.invalidData }
            seen[key] = metrics
            return TokenSpeedSample(outputTokens: Int(tokens), durationMilliseconds: Double(end - start),
                recordedAt: date, accountKey: scopeKey, requestKey: "message:" + key)
        }

        private static func validID(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 128 }
        private static func recent(_ date: Date, now: Date) -> Bool {
            date <= now && now.timeIntervalSince(date) <= TokenSpeed.maximumAge
        }
        private static func turnKey(_ id: String, session: UUID) -> String {
            CodexSessionTokenSpeedReader.fingerprint(Data("\(session.uuidString)|\(id)".utf8))
        }
        private mutating func invalidate(_ id: String, session: UUID, completed: Bool) {
            let key = Self.turnKey(id, session: session)
            invalidatedRequestKeys.insert("turn-progress:" + key)
            if completed { invalidatedRequestKeys.insert("turn:" + key) }
        }
        private func turnState(_ id: String) throws -> Turn {
            if let value = turns[id] { return value }
            guard turns.count < 4096 else { throw CodexSessionTokenSpeedError.invalidData }
            return Turn()
        }

        // A turn's counter is cumulative. Flush after the bounded backlog, never sum response counters.
        mutating func flush(now: Date) throws -> [TokenSpeedSample] {
            guard let session else { return [] }
            var result: [TokenSpeedSample] = []
            for id in turns.keys.sorted() {
                guard var turn = turns[id], !turn.aborted, let latest = turn.latest else { continue }
                let key = Self.turnKey(id, session: session)
                if let completion = turn.completion {
                    guard !completion.failed, let duration = completion.duration, duration > 0, duration <= 3_600_000,
                          Self.recent(completion.date, now: now), Self.recent(latest.date, now: now),
                          turn.completedSample != latest else { continue }
                    guard let sample = TokenSpeedSample(outputTokens: Int(latest.tokens), durationMilliseconds: Double(duration),
                        recordedAt: completion.date, accountKey: scopeKey, requestKey: "turn:" + key) else { continue }
                    result.append(sample)
                    turn.completedSample = latest
                } else if !turn.terminal, let start = turn.started, latest.date > start, latest.tokens > 0,
                          latest.date.timeIntervalSince(start) <= 3600, Self.recent(latest.date, now: now),
                          turn.progressSample != latest {
                    guard let sample = TokenSpeedSample(outputTokens: Int(latest.tokens),
                        durationMilliseconds: latest.date.timeIntervalSince(start) * 1000,
                        recordedAt: latest.date, accountKey: scopeKey,
                        requestKey: "turn-progress:" + key) else { continue }
                    result.append(sample)
                    turn.progressSample = latest
                }
                turns[id] = turn
            }
            return result.sorted { $0.recordedAt < $1.recordedAt }
        }
    }
    private struct Turn: Sendable {
        var started: Date?
        var completion: Completion?
        var responses: [String: Observation] = [:]
        var latest: Observation?
        var progressSample: Observation?
        var completedSample: Observation?
        var terminal = false
        var aborted = false
    }
    private struct Observation: Equatable, Sendable { let tokens: Int64; let date: Date }
    private struct Completion: Equatable, Sendable { let date: Date; let duration: Int64?; let failed: Bool }
    private struct Metrics: Equatable, Sendable { let tokens: Int64; let start: Int64; let end: Int64 }

    // Decode only IDs and numerical completion metadata; message bodies and creator identities stay unmaterialized.
    private struct Record: Decodable {
        let type: String
        let meta: Meta?
        let event: Event?
        let usage: Usage?
        let date: Date?
        private enum CodingKeys: String, CodingKey { case type, payload, timestamp }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            type = try values.decode(String.self, forKey: .type)
            meta = type == "session_meta" ? try values.decode(Meta.self, forKey: .payload) : nil
            event = type == "event_msg" ? try values.decode(Event.self, forKey: .payload) : nil
            usage = type == "token_usage_record" ? try values.decode(Usage.self, forKey: .payload) : nil
            if type == "token_usage_record" || event?.type == "task_started" || event?.type == "task_complete",
               let timestamp = try? values.decode(String.self, forKey: .timestamp), timestamp.utf8.count <= 64,
               timestamp.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$"#,
                   options: .regularExpression) != nil {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let parsed = formatter.date(from: timestamp) { date = parsed }
                else {
                    formatter.formatOptions = [.withInternetDateTime]
                    date = formatter.date(from: timestamp)
                }
            } else { date = nil }
        }
    }
    private struct Usage: Decodable {
        let threadID: String
        let turnID: String
        let responseID: String
        let tokens: Int64?
        private enum CodingKeys: String, CodingKey {
            case threadID = "thread_id", turnID = "turn_id", responseID = "response_id", counter = "turn_token_usage"
        }
        private struct Counter: Decodable { let output_tokens: Int64 }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            threadID = try values.decode(String.self, forKey: .threadID)
            turnID = try values.decode(String.self, forKey: .turnID)
            responseID = try values.decode(String.self, forKey: .responseID)
            tokens = (try? values.decode(Counter.self, forKey: .counter))?.output_tokens
        }
    }
    private struct Meta: Decodable {
        let id: String
        let historyMode: String?
        private enum CodingKeys: String, CodingKey { case id; case historyMode = "history_mode" }
    }
    private struct Event: Decodable {
        let type: String
        let threadID: String?
        let turnID: String?
        let item: Item?
        let tokens: Int64?
        let start: Int64?
        let end: Int64?
        let duration: Int64?
        let failed: Bool
        private enum CodingKeys: String, CodingKey {
            case type, item
            case threadID = "thread_id", turnID = "turn_id", tokens = "content_token_count"
            case start = "started_at_ms", end = "completed_at_ms"
            case duration = "duration_ms", error
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            type = try values.decode(String.self, forKey: .type)
            guard type == "item_completed" || type == "task_started" || type == "task_complete" || type == "turn_aborted" else {
                threadID = nil; turnID = nil; item = nil; tokens = nil; start = nil; end = nil; duration = nil; failed = false
                return
            }
            threadID = try values.decodeIfPresent(String.self, forKey: .threadID)
            turnID = try values.decodeIfPresent(String.self, forKey: .turnID)
            item = try values.decodeIfPresent(Item.self, forKey: .item)
            tokens = try? values.decode(Int64.self, forKey: .tokens)
            start = try? values.decode(Int64.self, forKey: .start)
            end = try? values.decode(Int64.self, forKey: .end)
            duration = try? values.decode(Int64.self, forKey: .duration)
            failed = values.contains(.error) && ((try? values.decodeNil(forKey: .error)) != true)
        }
    }
    private struct Item: Decodable { let type: String; let id: String? }
}
