import ServiceCatalog
import XCTest
@testable import ServerControl

final class PerServiceHostTests: XCTestCase {
    private func pair() -> Deployment {
        Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                   homeWGAddress: "10.8.0.2",
                   services: [.vaultwarden, .nextcloud, .dockerMailserver])
    }

    func testWithOneWorkerEveryServiceAnswersTheServicesHost() {
        let deployment = pair()
        for service in deployment.services {
            XCTAssertEqual(deployment.host(running: service), deployment.servicesHost)
        }
    }

    func testAPlacedServiceAnswersItsOwnMachine() throws {
        var deployment = pair()
        let entry = deployment.nodes.first { $0.legacySlot == .vps }!
        let third = DeploymentNode(id: UUID(),
                                   endpoint: HostEndpoint(host: "10.8.0.3", user: "root"),
                                   capabilities: [.worker], routedThrough: entry.id)
        try deployment.addNode(third)
        deployment.place(.nextcloud, on: third.id)

        XCTAssertEqual(deployment.host(running: .nextcloud), .node(third.id))
        // And only that one moved.
        XCTAssertEqual(deployment.host(running: .vaultwarden), deployment.servicesHost)
        XCTAssertEqual(deployment.host(running: .dockerMailserver), deployment.servicesHost)
    }

    func testAStalePlacementFallsBackToAWorker() {
        var deployment = pair()
        deployment.placement = ServicePlacement([ServiceID.nextcloud.rawValue: UUID()])
        XCTAssertEqual(deployment.host(running: .nextcloud), deployment.servicesHost)
    }

    func testTheIngressOnlyMachineIsNeverTheAnswer() {
        var deployment = pair()
        let entry = deployment.nodes.first { $0.legacySlot == .vps }!
        deployment.placement = ServicePlacement([ServiceID.nextcloud.rawValue: entry.id])
        XCTAssertEqual(deployment.host(running: .nextcloud), .home)
    }
}
