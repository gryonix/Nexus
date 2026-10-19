import ServiceCatalog
import XCTest
@testable import VPNTunnel

final class FleetSnapshotMergeTests: XCTestCase {
    private var url: URL!
    private var store: FleetSnapshotStore!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fleet-\(UUID().uuidString).json")
        store = FleetSnapshotStore(fileURL: url)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func devices(_ id: ServiceID, _ count: Int, _ names: [String] = []) -> FleetSnapshot.ProtocolDevices {
        FleetSnapshot.ProtocolDevices(protocolID: id, deviceCount: count, deviceNames: names)
    }

    func testTheFirstReadingCreatesTheServer() {
        let id = UUID()
        store.upsertServer(id: id, name: "Home", protocols: [devices(.wireguardVPN, 3)], failure: nil)

        let snapshot = try? XCTUnwrap(store.read())
        XCTAssertEqual(snapshot?.servers.count, 1)
        XCTAssertEqual(snapshot?.servers.first?.name, "Home")
        XCTAssertEqual(snapshot?.deviceCount, 3)
    }

    func testASecondProtocolIsMergedRatherThanReplacingTheFirst() {
        let id = UUID()
        store.upsertServer(id: id, name: "Home", protocols: [devices(.wireguardVPN, 3)], failure: nil)
        store.upsertServer(id: id, name: "Home", protocols: [devices(.openVPN, 2)], failure: nil)

        let server = store.read()?.servers.first
        XCTAssertEqual(server?.protocols.count, 2)
        XCTAssertEqual(server?.deviceCount, 5)
    }

    func testRereadingAProtocolReplacesItsCount() {
        let id = UUID()
        store.upsertServer(id: id, name: "Home", protocols: [devices(.wireguardVPN, 3)], failure: nil)
        store.upsertServer(id: id, name: "Home", protocols: [devices(.wireguardVPN, 4)], failure: nil)

        let server = store.read()?.servers.first
        XCTAssertEqual(server?.protocols.count, 1)
        XCTAssertEqual(server?.deviceCount, 4)
    }

    func testASecondServerDoesNotDisturbTheFirst() {
        let home = UUID(), relay = UUID()
        store.upsertServer(id: home, name: "Home", protocols: [devices(.wireguardVPN, 3)], failure: nil)
        store.upsertServer(id: relay, name: "Relay", protocols: [devices(.wireguardVPN, 1)], failure: nil)

        let snapshot = store.read()
        XCTAssertEqual(snapshot?.servers.count, 2)
        XCTAssertEqual(snapshot?.deviceCount, 4)
        XCTAssertEqual(snapshot?.reachableServerCount, 2)
    }

    func testAFailureIsRecordedWithoutErasingWhatWasKnown() {
        let id = UUID()
        store.upsertServer(id: id, name: "Home", protocols: [devices(.wireguardVPN, 3)], failure: nil)
        store.upsertServer(id: id, name: "Home", protocols: [], failure: "the agent bridge did not start")

        let server = store.read()?.servers.first
        XCTAssertEqual(server?.deviceCount, 3)
        XCTAssertEqual(server?.failure, "the agent bridge did not start")
        XCTAssertEqual(store.read()?.reachableServerCount, 0)
    }

    /// A server that answers again stops being a failure
    func testASuccessfulRereadClearsTheFailure() {
        let id = UUID()
        store.upsertServer(id: id, name: "Home", protocols: [], failure: "unreachable")
        store.upsertServer(id: id, name: "Home", protocols: [devices(.wireguardVPN, 2)], failure: nil)

        XCTAssertNil(store.read()?.servers.first?.failure)
        XCTAssertEqual(store.read()?.reachableServerCount, 1)
    }

    func testARenamedServerIsRenamedRatherThanDuplicated() {
        let id = UUID()
        store.upsertServer(id: id, name: "Home", protocols: [devices(.wireguardVPN, 1)], failure: nil)
        store.upsertServer(id: id, name: "Home server", protocols: [devices(.wireguardVPN, 1)], failure: nil)

        XCTAssertEqual(store.read()?.servers.count, 1)
        XCTAssertEqual(store.read()?.servers.first?.name, "Home server")
    }

    func testProtocolOrderDoesNotDependOnReadingOrder() {
        let first = UUID(), second = UUID()
        store.upsertServer(id: first, name: "A", protocols: [devices(.wireguardVPN, 1)], failure: nil)
        store.upsertServer(id: first, name: "A", protocols: [devices(.openVPN, 1)], failure: nil)

        let other = FleetSnapshotStore(fileURL: url.deletingLastPathComponent()
            .appendingPathComponent("fleet-\(UUID().uuidString).json"))
        other.upsertServer(id: second, name: "A", protocols: [devices(.openVPN, 1)], failure: nil)
        other.upsertServer(id: second, name: "A", protocols: [devices(.wireguardVPN, 1)], failure: nil)

        XCTAssertEqual(store.read()?.servers.first?.protocols.map(\.protocolID),
                       other.read()?.servers.first?.protocols.map(\.protocolID))
    }

    func testWritingTheTunnelDoesNotFreshenTheFleetReading() throws {
        store.upsertServer(id: UUID(), name: "Home", protocols: [devices(.wireguardVPN, 1)],
                           failure: nil, at: Date(timeIntervalSince1970: 1_000_000))
        store.writeTunnel(TunnelSnapshot(status: .connected(since: Date()), isSimulated: true))

        XCTAssertEqual(try XCTUnwrap(store.read()).generatedAt,
                       Date(timeIntervalSince1970: 1_000_000))
    }

    // MARK: - Forgetting

    func testForgettingAServerRemovesItAndLeavesTheOthers() {
        let home = UUID(), relay = UUID()
        store.upsertServer(id: home, name: "Home", protocols: [devices(.wireguardVPN, 3)], failure: nil)
        store.upsertServer(id: relay, name: "Relay", protocols: [devices(.wireguardVPN, 1)], failure: nil)

        XCTAssertTrue(store.forgetServer(id: home))
        XCTAssertEqual(store.read()?.servers.map(\.id), [relay])
    }

    func testForgettingAnUnknownServerChangesNothing() {
        store.upsertServer(id: UUID(), name: "Home", protocols: [devices(.wireguardVPN, 1)], failure: nil)
        XCTAssertFalse(store.forgetServer(id: UUID()))
        XCTAssertEqual(store.read()?.servers.count, 1)
    }
}
