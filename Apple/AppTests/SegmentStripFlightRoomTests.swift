#if os(iOS)
import UIKit
import XCTest

@testable import gryonixNexus

final class SegmentStripFlightRoomTests: XCTestCase {
    private let bar = CGRect(x: 0, y: 0, width: 360, height: 62)
    private let scrollingContent: CGFloat = 460
    private var radius: CGFloat { bar.height / 2 }

    func testStripAtItsStartKeepsTheFullRoomAtTheLeadingEnd() {
        let room = SegmentStripView.flightRoom(bar: bar, contentWidth: scrollingContent, offset: 0)
        XCTAssertEqual(room.minX, -32, accuracy: 0.01)
    }

    func testScrolledStripHandsTheLeadingEndBackToTheBarsOwnShape() {
        let room = SegmentStripView.flightRoom(bar: bar, contentWidth: scrollingContent, offset: 80)
        XCTAssertEqual(room.minX, radius, accuracy: 0.01)
    }

    func testTrailingEndClosesOnceContentIsScrolledBehindIt() {
        let atStart = SegmentStripView.flightRoom(bar: bar, contentWidth: scrollingContent, offset: 0)
        XCTAssertEqual(atStart.maxX, bar.width - radius, accuracy: 0.01,
                       "100pt of content sits past the trailing end — nothing may be drawn out there")
        let atEnd = SegmentStripView.flightRoom(bar: bar,
                                                contentWidth: scrollingContent,
                                                offset: scrollingContent - bar.width)
        XCTAssertEqual(atEnd.maxX, bar.width + 32, accuracy: 0.01)
        XCTAssertEqual(atEnd.minX, radius, accuracy: 0.01)
    }

    func testNothingIsDrawnPastTheEndOnceTheStripHasMovedAtAll() {
        let restingInset: CGFloat = 5
        for tenths in 1...400 {
            let past = CGFloat(tenths) / 10
            let room = SegmentStripView.flightRoom(bar: bar,
                                                   contentWidth: scrollingContent,
                                                   offset: scrollingContent - bar.width - past)
            let capsule = bar.maxX - restingInset + past
            XCTAssertLessThanOrEqual(min(capsule, room.maxX), bar.maxX + 0.01,
                                     "glass shows past the trailing end \(past)pt into the drag")
        }
    }

    func testRoomClosesWithTheScrollRatherThanAtOnce() {
        let closesOver: CGFloat = 5
        let leading = stride(from: CGFloat(0), through: closesOver, by: 1).map {
            SegmentStripView.flightRoom(bar: bar, contentWidth: scrollingContent, offset: $0).minX
        }
        XCTAssertEqual(leading, leading.sorted(), "the room jumped back open mid-scroll")
        for (offset, edge) in zip(stride(from: CGFloat(0), through: closesOver, by: 1), leading) {
            XCTAssertEqual(edge, -32 + (radius + 32) * offset / closesOver, accuracy: 0.01,
                           "at offset \(offset)")
        }
    }

    func testStripWhoseSectionsAllFitKeepsTheRoomOnBothSides() {
        let room = SegmentStripView.flightRoom(bar: bar, contentWidth: bar.width, offset: 0)
        XCTAssertEqual(room, bar.insetBy(dx: -32, dy: -32))
    }

    func testOverscrollIsClampedToTheMargin() {
        let bounced = SegmentStripView.flightRoom(bar: bar, contentWidth: scrollingContent, offset: -50)
        XCTAssertEqual(bounced.minX, -32, accuracy: 0.01)
        let pastEnd = SegmentStripView.flightRoom(bar: bar, contentWidth: scrollingContent, offset: 999)
        XCTAssertEqual(pastEnd.maxX, bar.width + 32, accuracy: 0.01)
        XCTAssertGreaterThan(pastEnd.width, 0)
    }

    func testBothEndsClosedOnATinyBarLeaveNoRoomRatherThanANegativeOne() {
        let tiny = CGRect(x: 0, y: 0, width: 40, height: 62)
        let room = SegmentStripView.flightRoom(bar: tiny, contentWidth: 400, offset: 180)
        XCTAssertEqual(room.width, 0)
    }

    func testTheCapsuleKeepsItsRoomAboveAndBelowWhateverTheScroll() {
        for offset in stride(from: CGFloat(0), through: 100, by: 20) {
            let room = SegmentStripView.flightRoom(bar: bar, contentWidth: scrollingContent, offset: offset)
            XCTAssertEqual(room.minY, -32, accuracy: 0.01)
            XCTAssertEqual(room.maxY, bar.height + 32, accuracy: 0.01)
        }
    }
}
#endif
