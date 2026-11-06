import Foundation

/// Output tokens divided by the provider-reported observation duration.
public struct TokenSpeedSample: Equatable, Sendable {
    public let outputTokens: Int
    public let durationMilliseconds: Double
    public let recordedAt: Date
    public let accountKey: String
    public let requestKey: String
    public var tokensPerSecond: Double { Double(outputTokens) * 1000 / durationMilliseconds }

    public init?(outputTokens: Int, durationMilliseconds: Double, recordedAt: Date,
                 accountKey: String, requestKey: String) {
        guard (0...100_000_000).contains(outputTokens), durationMilliseconds.isFinite,
              durationMilliseconds > 0, durationMilliseconds <= 3_600_000,
              (Double(outputTokens) * 1000 / durationMilliseconds).isFinite,
              recordedAt.timeIntervalSince1970.isFinite,
              !accountKey.isEmpty, accountKey.utf8.count <= 128,
              !requestKey.isEmpty, requestKey.utf8.count <= 128 else { return nil }
        self.outputTokens = outputTokens; self.durationMilliseconds = durationMilliseconds
        self.recordedAt = recordedAt; self.accountKey = accountKey; self.requestKey = requestKey
    }
}

public enum TokenSpeedError: Error, Equatable, Sendable {
    case invalidPayload, invalidAccount, unavailable, alreadyRunning
}

public enum TokenSpeed {
    public static let maximumAge: TimeInterval = 900
    static let maximumPayloadBytes = 1_048_576

}
