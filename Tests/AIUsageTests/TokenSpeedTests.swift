import XCTest
@testable import AIUsagePlugin

final class TokenSpeedTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    func testSampleCannotRepresentInvalidMeasurement() {
        XCTAssertNil(TokenSpeedSample(outputTokens: -1, durationMilliseconds: 1, recordedAt: now, accountKey: "a", requestKey: "b"))
        XCTAssertNil(TokenSpeedSample(outputTokens: 1, durationMilliseconds: 0, recordedAt: now, accountKey: "a", requestKey: "b"))
        XCTAssertNil(TokenSpeedSample(outputTokens: 1, durationMilliseconds: .infinity, recordedAt: now, accountKey: "a", requestKey: "b"))
        XCTAssertNil(TokenSpeedSample(outputTokens: 100_000_000, durationMilliseconds: 1e-300, recordedAt: now, accountKey: "a", requestKey: "b"))
    }
}
