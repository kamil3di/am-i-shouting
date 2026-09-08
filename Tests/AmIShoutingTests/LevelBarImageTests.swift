import AppKit
import XCTest
@testable import AmIShouting

/// The menu bar item is a drawn image, so the "does it actually turn red"
/// question is answered by reading pixels back out of it.
final class LevelBarImageTests: XCTestCase {

    private func pixels(fill: Double, thresholdMark: Double = 0.7, color: NSColor) throws -> NSBitmapImageRep {
        let image = LevelBarImage.make(fill: fill, thresholdMark: thresholdMark, color: color)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        return try XCTUnwrap(NSBitmapImageRep(data: tiff))
    }

    /// A little way into the filled part of the bar, vertically centred.
    private func fillColor(_ rep: NSBitmapImageRep) throws -> NSColor {
        let color = try XCTUnwrap(rep.colorAt(x: 3, y: rep.pixelsHigh / 2))
        return try XCTUnwrap(color.usingColorSpace(.sRGB))
    }

    func testImageMatchesTheMenuBarSlot() throws {
        let rep = try pixels(fill: 0.5, color: .systemGreen)
        XCTAssertEqual(rep.pixelsWide, Int(LevelBarImage.size.width))
        XCTAssertEqual(rep.pixelsHigh, Int(LevelBarImage.size.height))
    }

    func testShoutingDrawsRed() throws {
        let color = try fillColor(try pixels(fill: 1, color: LoudnessState.shouting.nsColor))
        XCTAssertGreaterThan(color.redComponent, 0.8)
        XCTAssertLessThan(color.greenComponent, 0.5)
    }

    func testNormalDrawsGreen() throws {
        let color = try fillColor(try pixels(fill: 1, color: LoudnessState.normal.nsColor))
        XCTAssertGreaterThan(color.greenComponent, 0.6)
        XCTAssertLessThan(color.redComponent, 0.5)
    }

    func testLoudDrawsYellow() throws {
        let color = try fillColor(try pixels(fill: 1, color: LoudnessState.loud.nsColor))
        XCTAssertGreaterThan(color.redComponent, 0.7)
        XCTAssertGreaterThan(color.greenComponent, 0.6)
        XCTAssertLessThan(color.blueComponent, 0.4)
    }

    /// Each state has to be visually distinct, otherwise the whole point of the
    /// colour is lost.
    func testEveryStateHasItsOwnColour() {
        let states: [LoudnessState] = [.quiet, .normal, .loud, .shouting]
        let colours = states.compactMap { $0.nsColor.usingColorSpace(.sRGB)?.description }
        XCTAssertEqual(Set(colours).count, states.count)
    }

    func testFillGrowsWithLevel() throws {
        let quiet = try pixels(fill: 0.2, color: .systemGreen)
        let loud = try pixels(fill: 0.9, color: .systemGreen)
        let x = Int(LevelBarImage.size.width) - 4
        let y = Int(LevelBarImage.size.height) / 2

        let quietFarRight = try XCTUnwrap(quiet.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        let loudFarRight = try XCTUnwrap(loud.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
        XCTAssertLessThan(quietFarRight.greenComponent, loudFarRight.greenComponent,
                          "the right end of the bar should only be green when the level is high")
    }

    /// At fill 0 there is still a visible track, but nothing coloured.
    func testEmptyBarDrawsNoFill() throws {
        let rep = try pixels(fill: 0, color: .systemRed)
        let color = try fillColor(rep)
        XCTAssertLessThan(color.redComponent - color.blueComponent, 0.2, "no red tint when silent")
    }

    func testThresholdTickIsDrawn() throws {
        let rep = try pixels(fill: 0, thresholdMark: 0.5, color: .systemGreen)
        let centre = Int(LevelBarImage.size.width * 0.5)
        // The tick is taller than the track, so it shows up above it.
        let aboveTrack = try XCTUnwrap(rep.colorAt(x: centre, y: 3)?.usingColorSpace(.sRGB))
        let farFromTick = try XCTUnwrap(rep.colorAt(x: 1, y: 3)?.usingColorSpace(.sRGB))
        XCTAssertGreaterThan(aboveTrack.alphaComponent, farFromTick.alphaComponent + 0.1,
                             "a mark should be visible where shouting starts")
    }
}
