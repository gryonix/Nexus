#if os(iOS)
import UIKit
import XCTest

@testable import gryonixNexus

final class SegmentStripColumnTests: XCTestCase {
    func testTwoSectionsAreHalfTheRowEach() {
        let columns = SegmentStripView.equalColumns(natural: [80, 60], available: 300)
        XCTAssertEqual(columns, [150, 150])
    }

    func testThreeSectionsAreAThirdOfTheRowEach() {
        let columns = try? XCTUnwrap(SegmentStripView.equalColumns(natural: [40, 90, 60],
                                                                   available: 300))
        XCTAssertEqual(columns ?? [], [100, 100, 100])
    }

    func testColumnsCoverTheRowWithNothingLeftOver() {
        let available: CGFloat = 401
        let columns = SegmentStripView.equalColumns(natural: Array(repeating: 20, count: 7),
                                                    available: available)
        XCTAssertEqual((columns ?? []).reduce(0, +), available, accuracy: 0.0001)
        XCTAssertEqual(columns?.count, 7)
    }

    func testOneWordTooLongForItsShareEndsTheEqualDivision() {
        XCTAssertNil(SegmentStripView.equalColumns(natural: [40, 130, 60], available: 300))
    }

    func testAWordTooLongForItsShareStillGetsARowThatCoversTheBar() {
        let natural: [CGFloat] = [40, 130, 60]
        let columns = try? XCTUnwrap(SegmentStripView.filledColumns(natural: natural,
                                                                    available: 300))
        XCTAssertEqual((columns ?? []).reduce(0, +), 300, accuracy: 0.0001)
        XCTAssertNotNil(columns)
        for (index, width) in (columns ?? []).enumerated() {
            XCTAssertGreaterThanOrEqual(width, natural[index], "section \(index) was squeezed")
        }
        XCTAssertEqual((columns ?? [])[1], columns?.max())
    }

    func testTheFilledRowPrefersEqualSharesWhenTheyFit() {
        XCTAssertEqual(SegmentStripView.filledColumns(natural: [80, 60], available: 300),
                       [150, 150])
    }

    func testAWordExactlyAsWideAsItsShareStillFits() {
        XCTAssertEqual(SegmentStripView.equalColumns(natural: [150, 100], available: 300),
                       [150, 150])
    }

    func testNoSectionsOrNoRoomIsNoDivision() {
        XCTAssertNil(SegmentStripView.equalColumns(natural: [], available: 300))
        XCTAssertNil(SegmentStripView.equalColumns(natural: [40, 40], available: 0))
    }
}
#endif
