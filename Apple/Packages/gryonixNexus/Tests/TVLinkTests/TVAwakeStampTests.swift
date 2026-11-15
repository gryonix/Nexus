import Foundation
import Network
import XCTest

@testable import TVLink

/// The TV stamps its Bonjour record; phones read the stamp
final class TVAwakeStampTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let endpoint = NWEndpoint.hostPort(host: "192.0.2.4", port: 47_390)

    func testTheRecordCarriesTheIDAndTheTime() {
        let service = TVLinkServer.advertisement(for: TVPeer(id: "tv-1", name: "draco"), now: now)
        guard let record = service.txtRecordObject else { return XCTFail("no TXT record") }
        XCTAssertEqual(record[TVLinkService.idKey], "tv-1")
        XCTAssertEqual(TVBrowser.awakeTime(record[TVLinkService.awakeKey]), now)
    }

    func testAStampWithinThreeMinutesIsAwake() {
        let tv = TVNearby(name: "draco", tvID: "tv-1", endpoint: endpoint, awakeAt: now.addingTimeInterval(-170))
        XCTAssertTrue(tv.isAwake(now: now))
    }

    func testAnOldStampIsAsleep() {
        let tv = TVNearby(name: "draco", tvID: "tv-1", endpoint: endpoint, awakeAt: now.addingTimeInterval(-200))
        XCTAssertFalse(tv.isAwake(now: now))
    }

    func testNoStampOrAnUnreadableOneIsAsleep() {
        XCTAssertFalse(TVNearby(name: "draco", tvID: "tv-1", endpoint: endpoint).isAwake(now: now))
        XCTAssertNil(TVBrowser.awakeTime("soon"))
    }
}
