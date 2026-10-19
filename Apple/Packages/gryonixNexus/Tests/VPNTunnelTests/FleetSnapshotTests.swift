import ServiceCatalog
import XCTest
@testable import VPNTunnel

final class FleetSnapshotTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func store() -> FleetSnapshotStore {
        FleetSnapshotStore(fileURL: directory.appendingPathComponent("snapshot.json"))
    }

    private func server(name: String = "Home", devices: Int = 2,
                        failure: String? = nil) -> FleetSnapshot.Server {
        FleetSnapshot.Server(id: UUID(), name: name,
                             protocols: [.init(protocolID: .wireguardVPN, deviceCount: devices,
                                               deviceNames: ["iPhone", "Mac"])],
                             failure: failure)
    }

    func testAnUnwrittenSnapshotReadsAsNothingRatherThanAsZeroes() {
        XCTAssertNil(store().read())
    }

    func testWhatIsWrittenComesBack() {
        let store = store()
        store.write(FleetSnapshot(servers: [server()], tunnel: .off))
        let read = store.read()
        XCTAssertEqual(read?.servers.first?.name, "Home")
        XCTAssertEqual(read?.deviceCount, 2)
    }

    func testATunnelUpdateLeavesTheFleetReadingsAgeAlone() {
        let store = store()
        let taken = Date(timeIntervalSince1970: 1_000)
        store.writeServers([server()], at: taken)
        store.writeTunnel(TunnelSnapshot(status: .connecting, isSimulated: true))

        let read = store.read()
        XCTAssertEqual(read?.generatedAt, taken)
        XCTAssertEqual(read?.tunnel.status, .connecting)
        XCTAssertEqual(read?.servers.count, 1)
    }

    func testAFleetUpdateLeavesTheTunnelAlone() {
        let store = store()
        store.writeTunnel(TunnelSnapshot(status: .connected(since: Date(timeIntervalSince1970: 5)),
                                         profileName: "iPhone", isSimulated: true))
        store.writeServers([server()])
        XCTAssertEqual(store.read()?.tunnel.profileName, "iPhone")
    }

    func testAFailedServerKeepsItsCountsAlongsideTheFailure() {
        let entry = server(devices: 3, failure: "Connection refused")
        XCTAssertEqual(entry.deviceCount, 3)
        XCTAssertNotNil(entry.failure)
        let snapshot = FleetSnapshot(servers: [entry, server()])
        XCTAssertEqual(snapshot.reachableServerCount, 1)
        XCTAssertEqual(snapshot.deviceCount, 5)
    }

    func testTheProtocolSummaryNamesOnlyProtocolsThatHoldDevices() {
        let entry = FleetSnapshot.Server(
            id: UUID(), name: "Home",
            protocols: [.init(protocolID: .wireguardVPN, deviceCount: 2),
                        .init(protocolID: .openVPN, deviceCount: 0)])
        XCTAssertEqual(entry.protocolSummary, "WireGuard")
    }

    func testAConnectedStatusSurvivesEncodingWithItsStartDate() throws {
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        let encoded = try JSONEncoder().encode(TunnelStatus.connected(since: since))
        let decoded = try JSONDecoder().decode(TunnelStatus.self, from: encoded)
        XCTAssertEqual(decoded, .connected(since: since))
        XCTAssertEqual(decoded.activeSince, since)
    }

    func testAgeIsMeasuredFromWhenTheReadingWasTakenNotFromWhenItWasWritten() {
        let snapshot = FleetSnapshot(generatedAt: Date().addingTimeInterval(-120))
        XCTAssertEqual(snapshot.age, 120, accuracy: 5)
    }

    // MARK: - Deep links

    func testEveryDestinationSurvivesTheRoundTrip() {
        let id = UUID()
        for destination in [AppLink.Destination.server(id), .tunnel, .app] {
            XCTAssertEqual(AppLink.destination(of: AppLink.url(for: destination)), destination)
        }
    }

    func testALinkThisAppDoesNotOwnIsRefused() {
        XCTAssertNil(AppLink.destination(of: URL(string: "https://example.com/server/x")!))
        XCTAssertNil(AppLink.destination(of: URL(string: "gryonixnexus://backups")!))
        XCTAssertNil(AppLink.destination(of: URL(string: "gryonixnexus://server/not-a-uuid")!))
    }
}
