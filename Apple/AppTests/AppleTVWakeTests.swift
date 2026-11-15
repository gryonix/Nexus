#if os(iOS)
import Network
import TVLink
import XCTest

@testable import gryonixNexus

/// The phone vouches unasked only to awake TVs
final class AppleTVWakeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let endpoint = NWEndpoint.hostPort(host: "192.0.2.4", port: 47_390)
    private let paired = [
        TVPairedTV(id: "tv-living", name: "draco", address: nil, pairedAt: Date()),
        TVPairedTV(id: "tv-sleeping", name: "orion", address: nil, pairedAt: Date()),
    ]

    private func seen(_ id: String, awake ago: TimeInterval?) -> TVNearby {
        TVNearby(name: id, tvID: id, endpoint: endpoint, awakeAt: ago.map { now.addingTimeInterval(-$0) })
    }

    func testATVWithAFreshStampIsVouchedTo() {
        let seen = [seen("tv-living", awake: 30)]
        XCTAssertEqual(AppleTVLink.awake(paired, seen: seen, now: now).map(\.id), ["tv-living"])
    }

    func testASleepingTVKeepsAnOldStampAndIsLeftAlone() {
        let seen = [seen("tv-living", awake: 30), seen("tv-sleeping", awake: 600)]
        XCTAssertEqual(AppleTVLink.awake(paired, seen: seen, now: now).map(\.id), ["tv-living"])
    }

    func testARecordWithoutAStampIsLeftAlone() {
        XCTAssertTrue(AppleTVLink.awake(paired, seen: [seen("tv-living", awake: nil)], now: now).isEmpty)
    }

    func testASleepingTVIsNotDialledByItsLastAddress() {
        XCTAssertTrue(AppleTVLink.awake(paired, seen: [], now: now).isEmpty)
    }

    func testConfirmingByHandReachesEveryTVBonjourSees() {
        let seen = [seen("tv-living", awake: 30), seen("tv-sleeping", awake: nil)]
        XCTAssertEqual(AppleTVLink.seen(paired, seen: seen).map(\.id), ["tv-living", "tv-sleeping"])
    }
}
#endif
