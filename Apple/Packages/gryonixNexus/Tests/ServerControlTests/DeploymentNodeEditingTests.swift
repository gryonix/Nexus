import ServiceCatalog
import XCTest
@testable import ServerControl

final class DeploymentNodeEditingTests: XCTestCase {
    private func pair() -> Deployment {
        Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                   homeWGAddress: "10.8.0.2",
                   services: [.vaultwarden, .nextcloud])
    }

    private func worker(routedThrough parent: UUID?, host: String = "10.8.0.3") -> DeploymentNode {
        DeploymentNode(id: UUID(), endpoint: HostEndpoint(host: host, user: "root"),
                       capabilities: [.worker], routedThrough: parent)
    }

    // MARK: - Adding

    func testAddingAThirdMachineStartsStoringTheList() throws {
        var deployment = pair()
        XCTAssertNil(deployment.storedNodes, "a shipped pair is derived, not stored")
        let entry = deployment.nodes.first { $0.legacySlot == .vps }!
        try deployment.addNode(worker(routedThrough: entry.id))
        XCTAssertEqual(deployment.nodes.count, 3)
        XCTAssertNotNil(deployment.storedNodes)
    }

    func testAMachineWithNoAddressIsRefused() {
        var deployment = pair()
        XCTAssertThrowsError(try deployment.addNode(worker(routedThrough: nil, host: "   "))) { error in
            XCTAssertEqual(error as? Deployment.NodeEditError, .noAddress)
        }
        XCTAssertNil(deployment.storedNodes, "a refused machine must not have grown the list")
    }

    /// The transport needs something to jump FROM
    func testAMachineReachedThroughAStrangerIsRefused() {
        var deployment = pair()
        XCTAssertThrowsError(try deployment.addNode(worker(routedThrough: UUID()))) { error in
            XCTAssertEqual(error as? Deployment.NodeEditError, .unknownParent)
        }
    }

    func testALoopIsRefused() throws {
        var deployment = pair()
        let entry = deployment.nodes.first { $0.legacySlot == .vps }!
        let third = worker(routedThrough: entry.id)
        try deployment.addNode(third)
        var loop = entry
        loop.routedThrough = third.id
        XCTAssertThrowsError(try deployment.addNode(loop)) { error in
            XCTAssertEqual(error as? Deployment.NodeEditError, .parentLoop)
        }
    }

    // MARK: - Removing

    func testRemovingAMachineOthersAreReachedThroughIsRefused() throws {
        var deployment = pair()
        let entry = deployment.nodes.first { $0.legacySlot == .vps }!
        try deployment.addNode(worker(routedThrough: entry.id))
        XCTAssertThrowsError(try deployment.removeNode(entry.id)) { error in
            XCTAssertEqual(error as? Deployment.NodeEditError, .stillAParent)
        }
    }

    func testRemovingTheLastWorkerIsRefused() throws {
        var deployment = pair()
        let home = deployment.nodes.first { $0.legacySlot == .home }!
        XCTAssertThrowsError(try deployment.removeNode(home.id)) { error in
            XCTAssertEqual(error as? Deployment.NodeEditError, .lastWorker)
        }
    }

    func testRemovingAMachineClearsWhatWasPlacedOnIt() throws {
        var deployment = pair()
        let entry = deployment.nodes.first { $0.legacySlot == .vps }!
        let third = worker(routedThrough: entry.id)
        try deployment.addNode(third)
        deployment.place(.nextcloud, on: third.id)
        XCTAssertEqual(deployment.placement?[.nextcloud], third.id)

        try deployment.removeNode(third.id)
        XCTAssertNil(deployment.placement?[.nextcloud])
    }

    // MARK: - Placing

    func testPlacingAServiceIsReadBackByTheLookup() throws {
        var deployment = pair()
        let entry = deployment.nodes.first { $0.legacySlot == .vps }!
        let third = worker(routedThrough: entry.id)
        try deployment.addNode(third)
        deployment.place(.nextcloud, on: third.id)

        XCTAssertEqual(deployment.node(running: .nextcloud, placement: deployment.placement!)?.id, third.id)
        XCTAssertNotEqual(deployment.node(running: .vaultwarden, placement: deployment.placement!)?.id,
                          third.id)
    }

    func testClearingTheLastPlacementLeavesNothingStored() {
        var deployment = pair()
        let home = deployment.nodes.first { $0.legacySlot == .home }!
        deployment.place(.nextcloud, on: home.id)
        XCTAssertNotNil(deployment.placement)
        deployment.place(.nextcloud, on: nil)
        XCTAssertNil(deployment.placement)
    }

    // MARK: - On disk

    func testADeploymentWithoutExtraMachinesEncodesNoNewKeys() throws {
        let data = try JSONEncoder().encode(pair())
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("storedNodes"))
        XCTAssertFalse(json.contains("placement"))
    }

    func testPlacementSurvivesARoundTrip() throws {
        var deployment = pair()
        let home = deployment.nodes.first { $0.legacySlot == .home }!
        deployment.place(.nextcloud, on: home.id)
        let restored = try JSONDecoder().decode(Deployment.self,
                                                from: JSONEncoder().encode(deployment))
        XCTAssertEqual(restored.placement?[.nextcloud], home.id)
    }
}
