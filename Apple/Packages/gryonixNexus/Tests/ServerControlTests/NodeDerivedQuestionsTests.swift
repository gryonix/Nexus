import ServiceCatalog
import XCTest
@testable import ServerControl

final class NodeDerivedQuestionsTests: XCTestCase {
    private func single() -> Deployment {
        Deployment(name: "A", topology: .singleHost, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"))
    }

    private func pair() -> Deployment {
        Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", port: 2222, user: "admin"),
                   homeWGAddress: "10.8.0.2")
    }

    private func thirdWorker(of deployment: Deployment) -> DeploymentNode {
        DeploymentNode(id: UUID(),
                       name: "Second worker",
                       endpoint: HostEndpoint(host: "10.8.0.3", port: 2222, user: "admin"),
                       capabilities: [.worker],
                       routedThrough: deployment.ingressNode?.id)
    }

    // MARK: - The two shapes that are on disk today

    func testASingleHostAnswersExactlyAsTheEnumBranchDid() {
        let deployment = single()
        XCTAssertFalse(deployment.isMultiHost)
        XCTAssertFalse(deployment.hasRelayIngress, "one machine terminating AND running is not a relay")
        XCTAssertFalse(deployment.hasHomeHost)
        XCTAssertEqual(deployment.servicesHost, .vps)
        XCTAssertEqual(deployment.workerHosts, [.vps])
    }

    func testTheRelayPairAnswersExactlyAsTheEnumBranchDid() {
        let deployment = pair()
        XCTAssertTrue(deployment.isMultiHost)
        XCTAssertTrue(deployment.hasRelayIngress)
        XCTAssertTrue(deployment.hasHomeHost)
        XCTAssertEqual(deployment.servicesHost, .home)
        XCTAssertEqual(deployment.workerHosts, [.home])
    }

    func testAPairWithoutATunnelAddressHasNoHomeHost() {
        var deployment = pair()
        deployment.homeWGAddress = nil
        XCTAssertFalse(deployment.hasHomeHost)
        deployment.homeWGAddress = ""
        XCTAssertFalse(deployment.hasHomeHost)
    }

    // MARK: - The shapes the enum could not express

    /// Two workers and no relay: multi-host, but nothing is ingress-only
    func testTwoWorkersWithNoRelayAreMultiHostWithoutARelayIngress() {
        var deployment = single()
        let extra = DeploymentNode(id: UUID(),
                                   endpoint: HostEndpoint(host: "192.168.1.50", user: "root"),
                                   capabilities: [.worker])
        deployment.storedNodes = deployment.derivedNodes + [extra]

        XCTAssertTrue(deployment.isMultiHost)
        XCTAssertFalse(deployment.hasRelayIngress, "no machine here is ingress-only")
        XCTAssertFalse(deployment.hasHomeHost, "a node that routes through nobody is not behind anything")
        XCTAssertEqual(deployment.servicesHost, .vps, "the first worker still answers, unchanged")
        XCTAssertEqual(deployment.workerHosts, [.vps, .node(extra.id)])
    }

    /// A third worker behind the relay
    func testAThirdWorkerJoinsWorkerHostsWithoutMovingTheDefaultHost() {
        var deployment = pair()
        let extra = thirdWorker(of: deployment)
        deployment.storedNodes = deployment.derivedNodes + [extra]

        XCTAssertTrue(deployment.isMultiHost)
        XCTAssertTrue(deployment.hasRelayIngress)
        XCTAssertTrue(deployment.hasHomeHost)
        XCTAssertEqual(deployment.servicesHost, .home,
                       "adding a machine must not move where unplaced work goes")
        XCTAssertEqual(deployment.workerHosts, [.home, .node(extra.id)])
    }

    func testAMachineAddedAfterTheSlotsIsAddressedByItsOwnId() {
        var deployment = pair()
        let extra = thirdWorker(of: deployment)
        deployment.storedNodes = deployment.derivedNodes + [extra]

        XCTAssertNil(extra.legacySlot)
        XCTAssertEqual(extra.sshHost, .node(extra.id))
        XCTAssertNil(extra.sshHost.slot, "nothing keyed by slot may claim to have found one")
    }

    func testOnlyAPlacementMovesAServiceOntoTheThirdMachine() {
        var deployment = pair()
        let extra = thirdWorker(of: deployment)
        deployment.storedNodes = deployment.derivedNodes + [extra]
        deployment.services = [.mailcow, .vaultwarden]

        XCTAssertEqual(deployment.host(running: .mailcow), .home,
                       "an unplaced service stays on the machine it has always been on")

        var placement = ServicePlacement()
        placement[.mailcow] = extra.id
        deployment.placement = placement
        XCTAssertEqual(deployment.host(running: .mailcow), .node(extra.id))
        XCTAssertEqual(deployment.host(running: .vaultwarden), .home,
                       "placing one service must not move the others")
    }

    func testAPlacementNamingTheRelayFallsBackToAWorker() {
        var deployment = pair()
        deployment.services = [.mailcow]
        var placement = ServicePlacement()
        placement[.mailcow] = deployment.ingressNode?.id
        deployment.placement = placement

        XCTAssertEqual(deployment.host(running: .mailcow), .home)
    }

    // MARK: - Teardown order with three machines

    func testBothWorkersAreTornDownBeforeTheRelayTheyAreReachedThrough() {
        var deployment = pair()
        let extra = thirdWorker(of: deployment)
        deployment.storedNodes = deployment.derivedNodes + [extra]

        let order = deployment.teardownOrder.map(\.id)
        let relayIndex = order.firstIndex(of: deployment.ingressNode?.id ?? UUID())
        XCTAssertNotNil(relayIndex)
        XCTAssertEqual(order.count, 3)
        for worker in deployment.nodes.filter(\.runsServices) {
            let index = order.firstIndex(of: worker.id)
            XCTAssertNotNil(index)
            XCTAssertLessThan(index ?? .max, relayIndex ?? .min,
                              "a worker cleaned after its relay is unreachable with its data still on it")
        }
    }
}
