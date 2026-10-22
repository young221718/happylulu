import XCTest
import AppKit
@testable import AIUsageIntegration

@MainActor
final class CodexIconTests: XCTestCase {
    func testOfficialGlyphHasTransparentBackgroundAndOpenCenter() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(CodexMenuBarIcon.loadPNG())))
        XCTAssertEqual(bitmap.pixelsWide, 32)
        XCTAssertEqual(bitmap.pixelsHigh, 32)
        XCTAssertEqual(bitmap.colorAt(x: 0, y: 0)?.alphaComponent, 0)
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 16, y: 16)?.alphaComponent), 0.1)
        var ink = 0
        for y in 0..<32 {
            for x in 0..<32 {
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if color.alphaComponent > 0.1 {
                    ink += 1
                    XCTAssertEqual(color.redComponent, color.greenComponent, accuracy: 0.01)
                    XCTAssertEqual(color.greenComponent, color.blueComponent, accuracy: 0.01)
                }
            }
        }
        XCTAssertGreaterThan(ink, 180)
        XCTAssertLessThan(ink, 600)
    }

    func testGlyphIsStableWithoutLookingUpInstalledApplicationArtwork() throws {
        XCTAssertEqual(try XCTUnwrap(CodexMenuBarIcon.loadPNG()), try XCTUnwrap(CodexMenuBarIcon.loadPNG()))
    }
}
