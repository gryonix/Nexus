import ServiceCatalog
import XCTest
@testable import ServerControl

final class DeploymentNodeTests: XCTestCase {
    private func single() -> Deployment {
        Deployment(name: "A", topology: .singleHost, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"))
    }

    private func pair() -> Deployment {
        Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", port: 2222, user: "admin"),
                   homeWGAddress: "10.8.0.2")
    }

    func testASingleHostIsOneNodeThatBothTerminatesAndRuns() {
        let nodes = single().nodes
        XCTAssertEqual(nodes.count, 1)
        XCTAssertTrue(nodes[0].terminatesPublicTraffic)
        XCTAssertTrue(nodes[0].runsServices)
        XCTAssertNil(nodes[0].routedThrough, "a node that is its own ingress routes through nobody")
        XCTAssertEqual(nodes[0].endpoint.host, "203.0.113.10")
    }

    func testScenarioBIsAnIngressThatRunsNothingAndAWorkerBehindIt() {
        let nodes = pair().nodes
        XCTAssertEqual(nodes.count, 2)

        let relay = nodes[0]
        XCTAssertTrue(relay.terminatesPublicTraffic)
        XCTAssertFalse(relay.runsServices, "the relay must not be described as running services")

        let home = nodes[1]
        XCTAssertTrue(home.runsServices)
        XCTAssertFalse(home.terminatesPublicTraffic)
        XCTAssertEqual(home.routedThrough, relay.id, "the worker must name its ingress")
    }

    func testTheWorkerIsReachedAtTheTunnelAddressWithTheEntryCredentials() {
        let home = pair().nodes[1]
        XCTAssertEqual(home.endpoint.host, "10.8.0.2")
        XCTAssertEqual(home.endpoint.port, 2222)
        XCTAssertEqual(home.endpoint.user, "admin")
    }

    /// Ids must survive a move to another device
    func testNodeIdsAreStableForAGivenDeployment() {
        let deployment = pair()
        XCTAssertEqual(deployment.nodes.map(\.id), deployment.nodes.map(\.id))

        let sameIDElsewhere = Deployment(id: deployment.id, name: "imported",
                                         topology: .vpsRelayWithHomeBackend,
                                         entry: HostEndpoint(host: "other", user: "root"),
                                         homeWGAddress: "10.8.0.2")
        XCTAssertEqual(sameIDElsewhere.nodes.map(\.id), deployment.nodes.map(\.id),
                       "the same deployment must produce the same node ids on any device")
    }

    func testTheTwoSlotsGetDifferentIdsAndNeitherIsTheDeploymentId() {
        let deployment = pair()
        let ids = deployment.nodes.map(\.id)
        XCTAssertNotEqual(ids[0], ids[1])
        XCTAssertFalse(ids.contains(deployment.id))
    }

    func testDifferentDeploymentsGetDifferentNodeIds() {
        let first = pair()
        let second = pair()
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertTrue(Set(first.nodes.map(\.id)).isDisjoint(with: Set(second.nodes.map(\.id))))
    }

    func testEveryMigratedNodeCarriesTheSlotItsSecretsAreStoredUnder() {
        XCTAssertEqual(single().nodes.map(\.legacySlot), [.vps])
        XCTAssertEqual(pair().nodes.map(\.legacySlot), [.vps, .home])
    }

    func testADeploymentWithoutExtraNodesWritesNoNodeList() throws {
        let data = try JSONEncoder().encode(pair())
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("storedNodes"), "an unchanged deployment must not gain a node list")
    }

    func testADeploymentStoredBeforeNodesExistedStillDerivesThem() throws {
        var encoded = try JSONEncoder().encode(pair())
        let restored = try JSONDecoder().decode(Deployment.self, from: encoded)
        XCTAssertNil(restored.storedNodes)
        XCTAssertEqual(restored.nodes.map(\.legacySlot), [.vps, .home])
        encoded = try JSONEncoder().encode(restored)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("storedNodes"))
    }

    func testAStoredListWinsOverTheDerivedPair() {
        var deployment = pair()
        let extra = DeploymentNode(id: UUID(),
                                   endpoint: HostEndpoint(host: "192.168.1.50", user: "root"),
                                   capabilities: [.worker])
        deployment.storedNodes = deployment.derivedNodes + [extra]
        XCTAssertEqual(deployment.nodes.count, 3)
        XCTAssertEqual(deployment.nodes.last?.id, extra.id)
    }

    func testTheServicesNodeIsTheWorkerAndTheIngressIsTheRelay() {
        let deployment = pair()
        XCTAssertEqual(deployment.servicesNode?.legacySlot, .home)
        XCTAssertEqual(deployment.ingressNode?.legacySlot, .vps)

        let alone = single()
        XCTAssertEqual(alone.servicesNode?.id, alone.ingressNode?.id,
                       "one machine doing both jobs is one node, not two")
    }
}
