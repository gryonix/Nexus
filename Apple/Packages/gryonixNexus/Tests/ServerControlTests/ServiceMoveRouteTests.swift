import ServiceCatalog
import XCTest
@testable import ServerControl

final class ServiceMoveRouteTests: XCTestCase {
    private func single(agent: Bool = true) -> Deployment {
        Deployment(name: "A", topology: .singleHost, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                   services: [.nextcloud, .vaultwarden], usesAgent: agent)
    }

    private func extra(host: String = "10.0.0.7") -> DeploymentNode {
        DeploymentNode(id: UUID(), name: "Second", endpoint: HostEndpoint(host: host, user: "admin"),
                       capabilities: [.worker])
    }

    private func relay() -> Deployment {
        Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                   homeWGAddress: "10.8.0.2", services: [.nextcloud], usesAgent: true)
    }

    func testTheFrontOfASingleHostIsThatHost() {
        let deployment = single()
        XCTAssertEqual(deployment.frontNode?.id, deployment.nodes[0].id)
    }

    func testTheFrontOfARelayIsTheHomeHalfThatAnswersItsOwnTraffic() {
        let deployment = relay()
        XCTAssertEqual(deployment.frontNode?.legacySlot, .home)
    }

    func testMovingOffTheFrontDialsTheOtherMachineAndMovingBackServesItLocally() throws {
        var deployment = single()
        let second = extra()
        try deployment.addNode(second)
        let out = try deployment.moveRoute(of: .nextcloud, to: second.id).get()
        XCTAssertEqual(out.source.id, deployment.nodes[0].id)
        XCTAssertNil(out.sourceEntryAddress)
        XCTAssertEqual(out.targetEntryAddress, "10.0.0.7")

        deployment.place(.nextcloud, on: second.id)
        let back = try deployment.moveRoute(of: .nextcloud, to: deployment.nodes[0].id).get()
        XCTAssertEqual(back.sourceEntryAddress, "10.0.0.7")
        XCTAssertNil(back.targetEntryAddress)
    }

    func testMovingBetweenTwoMachinesBehindTheFrontDialsBoth() throws {
        var deployment = single()
        let (second, third) = (extra(), extra(host: "10.0.0.8"))
        try deployment.addNode(second)
        try deployment.addNode(third)
        deployment.place(.nextcloud, on: second.id)
        let route = try deployment.moveRoute(of: .nextcloud, to: third.id).get()
        XCTAssertEqual(route.sourceEntryAddress, "10.0.0.7")
        XCTAssertEqual(route.targetEntryAddress, "10.0.0.8")
    }

    func testTheRefusalsNameTheirReason() throws {
        var deployment = single()
        let second = extra()
        try deployment.addNode(second)
        XCTAssertEqual(deployment.moveRoute(of: .nextcloud, to: deployment.nodes[0].id), .failure(.sameMachine))
        XCTAssertEqual(deployment.moveRoute(of: .nextcloud, to: UUID()), .failure(.unknownMachine))
        XCTAssertEqual(single(agent: false).moveRoute(of: .nextcloud, to: second.id), .failure(.noAgent))

        let relayOnly = DeploymentNode(id: UUID(), endpoint: HostEndpoint(host: "1.2.3.4", user: "r"),
                                       capabilities: [.ingress])
        try deployment.addNode(relayOnly)
        XCTAssertEqual(deployment.moveRoute(of: .nextcloud, to: relayOnly.id), .failure(.targetDoesNotRunServices))
    }

    func testAPureRelayWithNoWorkerThatAnswersItsOwnTrafficHasNoFront() {
        let ingress = DeploymentNode(id: UUID(), endpoint: HostEndpoint(host: "1.2.3.4", user: "r"),
                                     capabilities: [.ingress])
        let worker = DeploymentNode(id: UUID(), endpoint: HostEndpoint(host: "10.0.0.2", user: "r"),
                                    capabilities: [.worker])
        let other = DeploymentNode(id: UUID(), endpoint: HostEndpoint(host: "10.0.0.3", user: "r"),
                                   capabilities: [.worker])
        let deployment = Deployment(name: "C", topology: .singleHost, domain: "example.com",
                                    entry: HostEndpoint(host: "1.2.3.4", user: "r"),
                                    services: [.nextcloud], usesAgent: true,
                                    storedNodes: [ingress, worker, other])
        XCTAssertNil(deployment.frontNode)
        XCTAssertEqual(deployment.moveRoute(of: .nextcloud, to: other.id), .failure(.noFront))
    }

    func testOnlyServicesWithASiteABackupAndNoOtherPortsMove() {
        let context = single().serviceContext
        func movable(_ id: ServiceID) -> Bool {
            ServiceRegistry.service(id).map { ServiceMovePolicy.isMovable($0, context: context) } ?? false
        }
        XCTAssertTrue(movable(.nextcloud))
        for stays in [ServiceID.authelia, .adguardHome, .pihole, .mailcow, .wireguardVPN, .minecraftJava] {
            XCTAssertFalse(movable(stays), stays.rawValue)
        }
    }
}
