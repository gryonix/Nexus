import SwiftUI
import XCTest

@testable import gryonixNexus

/// The island is one size on every phone
final class IslandCompactTests: XCTestCase {
    /// The island's own height
    private let islandHeight: CGFloat = 36.3

    func testTheGlyphNeverOutgrowsTheIsland() {
        for scaled in stride(from: CGFloat(10), through: 60, by: 2.5) {
            let diameter = IslandCompact.glyphDiameter(scaled: scaled)
            XCTAssertLessThanOrEqual(diameter, IslandCompact.widestGlyph,
                                     "a \(scaled)pt text size draws a \(diameter)pt glyph")
            XCTAssertGreaterThanOrEqual(diameter, IslandCompact.narrowestGlyph,
                                        "a \(scaled)pt text size draws a \(diameter)pt glyph")
        }
    }

    func testTheGlyphFollowsTheTextSizeInBetween() {
        XCTAssertGreaterThan(IslandCompact.glyphDiameter(scaled: 21),
                             IslandCompact.glyphDiameter(scaled: 16),
                             "the glyph ignores the text size")
    }

    func testTheTrailingSideKeepsItsRoomAndNoMore() {
        XCTAssertEqual(IslandCompact.trailingWidth(scaled: 30), IslandCompact.timerWidth,
                       "a small text size narrows the clock below its own digits")
        XCTAssertEqual(IslandCompact.trailingWidth(scaled: 200), IslandCompact.widestTimer,
                       "an accessibility text size pushes the clock past the island")
    }

    func testTheClockGetsRoomForHoursOnlyWhenItShowsThem() {
        XCTAssertEqual(IslandCompact.trailingWidth(scaled: 32, elapsed: 600), IslandCompact.timerWidth,
                       "a ten-minute clock is given room for hours")
        XCTAssertEqual(IslandCompact.trailingWidth(scaled: 32, elapsed: 2 * 3600), IslandCompact.hoursTimerWidth,
                       "a two-hour clock has no room for its hours")
        XCTAssertLessThan(IslandCompact.timerWidth, IslandCompact.hoursTimerWidth)
    }

    func testTheGlyphLeavesMarginsInsideTheIsland() {
        XCTAssertLessThanOrEqual(IslandCompact.widestGlyph + 8, islandHeight,
                                 "a \(IslandCompact.widestGlyph)pt glyph in a \(islandHeight)pt island")
    }

    /// Apple's compact side on the 393pt screens, the narrower class
    private let compactSide: CGFloat = 52.33

    func testLimitsFollowApplesTable() {
        XCTAssertLessThanOrEqual(IslandCompact.sideLimit, compactSide)
        XCTAssertLessThanOrEqual(IslandCompact.widestTimer, compactSide)
        XCTAssertLessThanOrEqual(IslandCompact.heightLimit, 36.67)
    }

    @MainActor
    func testTheLabelTakesOnlyItsDigits() {
        for text in ["7%", "96%", "100%"] {
            let size = measured(CompactIslandLabel(text: text, tint: .blue))
            XCTAssertLessThanOrEqual(size.width, compactSide, "\(text) is \(size.width)pt wide")
            XCTAssertLessThanOrEqual(size.height, 36.67, "\(text) is \(size.height)pt tall")
        }
        XCTAssertLessThan(measured(CompactIslandLabel(text: "7%", tint: .blue)).width,
                          measured(CompactIslandLabel(text: "100%", tint: .blue)).width,
                          "short text is padded to a fixed width")
    }

    @MainActor
    func testTheGlyphTakesOnlyItsDiameter() {
        let size = measured(CompactIslandGlyph { diameter in Circle().frame(width: diameter, height: diameter) })
        XCTAssertLessThanOrEqual(size.width, IslandCompact.widestGlyph)
    }

    @MainActor
    private func measured<V: View>(_ view: V) -> CGSize {
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(in: CGSize(width: 400, height: 100))
    }
}
