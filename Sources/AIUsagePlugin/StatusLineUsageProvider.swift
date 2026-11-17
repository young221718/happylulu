import Foundation
import Darwin

public enum StatusLineUsageError: LocalizedError {
    case unavailable, invalidReport, staleReport, noWeeklyQuota
    public var errorDescription: String? {
        switch self {
        case .unavailable: return "사용량 파일을 읽지 못했습니다. 소유자 전용 일반 파일을 선택하세요."
        case .invalidReport: return "사용량 파일의 형식 또는 공급자가 맞지 않습니다."
        case .staleReport: return "사용량 파일이 오래되었거나 한도가 만료되었습니다. CLI에서 새 사용량을 내보내세요."
        case .noWeeklyQuota: return "이 연결은 주간 한도를 제공하지 않았습니다."
        }
    }
}

/// Passive, explicitly selected statusLine export; never launches a CLI or accesses credentials.
public struct StatusLineUsageProvider: UsageProvider {
    public static var exporterURL: URL? {
        // Packaged apps keep SwiftPM resources in Contents/Resources, not beside the .app.
        if let resources = Bundle.main.resourceURL {
            let installed = resources.appendingPathComponent("HappyLulu_AIUsagePlugin.bundle/export-ai-usage.py")
            if FileManager.default.isReadableFile(atPath: installed.path) { return installed }
        }
        guard Bundle.main.bundleURL.pathExtension != "app" else { return nil }
        return Bundle.module.url(forResource: "export-ai-usage", withExtension: "py")
    }
    public let providerID: String
    public let name: String
    public let reportPath: String
    public init(providerID: String, name: String, reportPath: String) {
        self.providerID = providerID; self.name = name; self.reportPath = reportPath
    }
    public func makeLoginAttempt() -> (any UsageLoginAttempt)? { nil }
    public func fetch() async throws -> UsageSnapshot {
        try Task.checkCancellation()
        guard reportPath.hasPrefix("/") else { throw StatusLineUsageError.unavailable }
        let fd = open(reportPath, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw StatusLineUsageError.unavailable }
        defer { close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG,
              before.st_uid == geteuid(), before.st_mode & 0o077 == 0 else { throw StatusLineUsageError.unavailable }
        guard before.st_size > 0, before.st_size <= 1_048_576 else { throw StatusLineUsageError.invalidReport }
        var data = Data(), bytes = [UInt8](repeating: 0, count: 8192)
        while true {
            try Task.checkCancellation()
            let count = read(fd, &bytes, bytes.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw StatusLineUsageError.unavailable
            }
            guard data.count + count <= 1_048_576 else { throw StatusLineUsageError.invalidReport }
            data.append(contentsOf: bytes.prefix(count))
        }
        var after = stat()
        guard fstat(fd, &after) == 0, before.st_size == after.st_size, data.count == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw StatusLineUsageError.invalidReport }
        let value = try Self.parse(data, providerID: providerID)
        try Task.checkCancellation()
        return value
    }
    static func parse(_ data: Data, providerID: String, now: Date = Date()) throws -> UsageSnapshot {
        guard data.count <= 1_048_576, let report = try? JSONDecoder().decode(Report.self, from: data),
              report.schema == 1, report.provider == providerID,
              report.observedAt.isFinite, report.observedAt > 0 else { throw StatusLineUsageError.invalidReport }
        let observed = Date(timeIntervalSince1970: report.observedAt)
        guard observed <= now.addingTimeInterval(5), now.timeIntervalSince(observed) <= 900 else {
            throw StatusLineUsageError.staleReport
        }
        let used: Double, reset: Double
        switch providerID {
        case "claude":
            guard let window = report.rate_limits?.seven_day else { throw StatusLineUsageError.noWeeklyQuota }
            used = window.used_percentage; reset = window.resets_at
        case "antigravity":
            guard let bucket = report.quota?["gemini-weekly"], bucket.disabled != true else {
                throw StatusLineUsageError.noWeeklyQuota
            }
            guard !bucket.remaining_fraction.isNaN, (0...1).contains(bucket.remaining_fraction),
                  let date = ISO8601DateFormatter().date(from: bucket.reset_time) else { throw StatusLineUsageError.invalidReport }
            // Preserve decimal quota fractions before converting to the shared percentage model.
            used = NSDecimalNumber(decimal: (1 - bucket.remaining_fraction) * 100).doubleValue
            reset = date.timeIntervalSince1970
        default: throw StatusLineUsageError.invalidReport
        }
        guard used.isFinite, (0...100).contains(used), reset.isFinite, reset < 253_402_300_800 else {
            throw StatusLineUsageError.invalidReport
        }
        guard reset > now.timeIntervalSince1970 else { throw StatusLineUsageError.staleReport }
        let accountKey: String?
        if providerID == "antigravity", let key = report.accountKey {
            guard key.count == 64, key.allSatisfy({ "0123456789abcdef".contains($0) }) else { throw StatusLineUsageError.invalidReport }
            accountKey = key
        } else { accountKey = nil }
        return UsageSnapshot(weekly: UsageWindow(usedPercent: used, windowDurationMins: 10_080, resetsAt: reset),
                             fetchedAt: observed, accountKey: accountKey)
    }
}

private struct Report: Decodable {
    let schema: Int
    let provider: String
    let observedAt: Double
    let accountKey: String?
    let rate_limits: Limits?
    let quota: [String: Bucket]?
    struct Limits: Decodable { let seven_day: Window? }
    struct Window: Decodable { let used_percentage: Double; let resets_at: Double }
    struct Bucket: Decodable { let remaining_fraction: Decimal; let reset_time: String; let disabled: Bool? }
}
