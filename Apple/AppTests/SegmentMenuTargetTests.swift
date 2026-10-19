import ServerControl
import XCTest
@testable import gryonixNexus

@MainActor
final class SegmentMenuTargetTests: XCTestCase {
    private let strip = CGRect(x: 16, y: 122, width: 408, height: 31)

    func testEverySegmentAnswersForItsOwnColumn() {
        for count in [2, 3, 6] {
            let width = strip.width / CGFloat(count)
            for index in 0..<count {
                let column = strip.minX + width * CGFloat(index)
                for x in [column + 0.5, column + width / 2, column + width - 0.5] {
                    XCTAssertEqual(
                        SegmentMenuPresenter.segment(at: x, in: strip, count: count), index,
                        "x=\(x) of \(count) segments named the wrong one")
                }
            }
        }
    }

    func testATouchOutsideTheStripNamesNoSegment() {
        XCTAssertNil(SegmentMenuPresenter.segment(at: strip.minX - 1, in: strip, count: 3))
        XCTAssertNil(SegmentMenuPresenter.segment(at: strip.maxX + 1, in: strip, count: 3))
        XCTAssertNil(SegmentMenuPresenter.segment(at: strip.midX, in: strip, count: 0))
    }

    func testTheAnchorFollowsTheFinger() {
        let left = SegmentMenuPresenter.anchor(at: strip.minX + 30, in: strip)
        let right = SegmentMenuPresenter.anchor(at: strip.maxX - 30, in: strip)
        XCTAssertLessThan(left.midX, right.midX - 100,
                          "two ends of the strip anchor in the same place")
        XCTAssertEqual(left.midX, strip.minX + 30, accuracy: 0.5)
        XCTAssertEqual(right.midX, strip.maxX - 30, accuracy: 0.5)
        for x in [strip.minX - 50, strip.maxX + 50] {
            let clamped = SegmentMenuPresenter.anchor(at: x, in: strip)
            XCTAssertGreaterThanOrEqual(clamped.minX, strip.minX - 0.5)
            XCTAssertLessThanOrEqual(clamped.maxX, strip.maxX + 0.5)
        }
    }

    func testTheColumnsTileTheStrip() {
        let count = 6
        var previous: CGRect?
        for index in 0..<count {
            let column = SegmentMenuPresenter.column(index, in: strip, count: count)
            XCTAssertEqual(column.width, strip.width / CGFloat(count), accuracy: 0.001)
            XCTAssertEqual(column.minX, previous?.maxX ?? strip.minX, accuracy: 0.001)
            previous = column
        }
        XCTAssertEqual(previous?.maxX ?? 0, strip.maxX, accuracy: 0.001)
    }
}

final class ServerGroupsTests: XCTestCase {
    private func deployment(_ name: String, _ tags: [String]) -> Deployment {
        Deployment(name: name, topology: .singleHost, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"), tags: tags)
    }

    func testTheStripIsBuiltFromWhatTheFleetSays() {
        let fleet = [deployment("a", ["prod"]), deployment("b", ["lab", "prod"])]
        XCTAssertEqual(ServerGroups.known(in: fleet), ["lab", "prod"])
        XCTAssertEqual(ServerGroups.known(in: [deployment("a", ["prod"])]), ["prod"])
        XCTAssertEqual(ServerGroups.known(in: [deployment("a", [])]), [])
    }

    func testMembershipIgnoresCase() {
        let fleet = [deployment("a", ["Prod"])]
        XCTAssertEqual(ServerGroups.members(of: "prod", in: fleet).count, 1)
        XCTAssertEqual(ServerGroups.setting(false, of: "prod", in: ["Prod", "lab"]), ["lab"])
        // Adding what is already there does not add it twice.
        XCTAssertEqual(ServerGroups.setting(true, of: "prod", in: ["Prod"]), ["prod"])
    }

    func testANameIsWhatIsLeftAfterTheSpaces() {
        XCTAssertEqual(ServerGroups.clean("  lab "), "lab")
        XCTAssertNil(ServerGroups.clean("   "))
        XCTAssertNil(ServerGroups.clean(""))
    }
}
