import VPNTunnel
import XCTest

@testable import gryonixNexus

/// The island hears state changes at once, traffic rarely
final class IslandUpdatePaceTests: XCTestCase {
    private let since = Date(timeIntervalSince1970: 1_000)

    func testTrafficTicksWaitForTheInterval() {
        var pace = IslandUpdatePace()
        let start = since.addingTimeInterval(10)
        XCTAssertTrue(pace.shouldSend(.connected(since: since), at: start))
        for second in 1..<Int(IslandUpdatePace.trafficInterval) {
            XCTAssertFalse(pace.shouldSend(.connected(since: since), at: start.addingTimeInterval(Double(second))),
                           "a tick every second redraws the island every second")
        }
        XCTAssertTrue(pace.shouldSend(.connected(since: since),
                                      at: start.addingTimeInterval(IslandUpdatePace.trafficInterval)))
    }

    func testAChangedStateGoesOutAtOnce() {
        var pace = IslandUpdatePace()
        let start = since.addingTimeInterval(10)
        XCTAssertTrue(pace.shouldSend(.connected(since: since), at: start))
        XCTAssertTrue(pace.shouldSend(.reasserting(since: since), at: start.addingTimeInterval(1)))
        XCTAssertTrue(pace.shouldSend(.connected(since: since), at: start.addingTimeInterval(2)))
    }

    func testANewSessionStartsFresh() {
        var pace = IslandUpdatePace()
        let start = since.addingTimeInterval(10)
        XCTAssertTrue(pace.shouldSend(.connected(since: since), at: start))
        pace.reset()
        XCTAssertTrue(pace.shouldSend(.connected(since: since), at: start.addingTimeInterval(1)))
    }
}
