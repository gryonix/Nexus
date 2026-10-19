import XCTest
@testable import ServerControl

/// The disk spelling of an `SSHHostID` — see `SSHHostIDPersistence`
final class SSHHostIDPersistenceTests: XCTestCase {
    func testTheTwoSlotsKeepTheSpellingsAlreadyOnDisk() {
        XCTAssertEqual(SSHHostID.vps.persistedRaw, "vps")
        XCTAssertEqual(SSHHostID.home.persistedRaw, "home")
        XCTAssertEqual(SSHHostID(persistedRaw: "vps"), .vps)
        XCTAssertEqual(SSHHostID(persistedRaw: "home"), .home)
    }

    func testANodeRoundTripsThroughItsId() {
        let id = UUID()
        let raw = SSHHostID.node(id).persistedRaw
        XCTAssertEqual(raw, "node:\(id.uuidString)")
        XCTAssertEqual(SSHHostID(persistedRaw: raw), .node(id))
    }

    func testAnUnknownSpellingFallsBackToTheEntryMachine() {
        XCTAssertEqual(SSHHostID(persistedRaw: ""), .vps)
        XCTAssertEqual(SSHHostID(persistedRaw: "node:not-a-uuid"), .vps)
        XCTAssertEqual(SSHHostID(persistedRaw: "relay"), .vps)
    }

    func testTwoDifferentNodesDoNotCollide() {
        let a = SSHHostID.node(UUID())
        let b = SSHHostID.node(UUID())
        XCTAssertNotEqual(a.persistedRaw, b.persistedRaw)
    }
}
