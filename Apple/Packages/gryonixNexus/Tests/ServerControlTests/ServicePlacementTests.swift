import ServiceCatalog
import XCTest
@testable import ServerControl

final class ServicePlacementTests: XCTestCase {
    private func pair() -> Deployment {
        Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                   homeWGAddress: "10.8.0.2",
                   services: [.vaultwarden, .nextcloud])
    }

    private func single() -> Deployment {
        Deployment(name: "A", topology: .singleHost, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                   services: [.vaultwarden])
    }

    func testWithNoPlacementEveryServiceLandsOnTheWorker() {
        let deployment = pair()
        for service in deployment.services {
            XCTAssertEqual(deployment.node(running: service)?.legacySlot, .home,
                           "\(service.rawValue) must land on the services host")
        }
    }

    func testOnASingleHostTheOnlyNodeRunsEverything() {
        let deployment = single()
        XCTAssertEqual(deployment.node(running: .vaultwarden)?.id, deployment.nodes[0].id)
    }

    func testAServiceIsNeverPlacedOnAnIngressOnlyNode() {
        let deployment = pair()
        let relay = deployment.nodes[0]
        var placement = ServicePlacement()
        placement[.vaultwarden] = relay.id

        XCTAssertEqual(deployment.node(running: .vaultwarden, placement: placement)?.legacySlot, .home,
                       "a service placed on a node that runs nothing must fall back to a worker")
    }

    func testAPlacementNamingAMissingNodeFallsBackInsteadOfFailing() {
        let deployment = pair()
        var placement = ServicePlacement()
        placement[.nextcloud] = UUID()

        XCTAssertNotNil(deployment.node(running: .nextcloud, placement: placement))
        XCTAssertEqual(deployment.node(running: .nextcloud, placement: placement)?.legacySlot, .home)
    }

    func testServicesGroupByNode() {
        let deployment = pair()
        let grouped = deployment.servicesByNode()
        XCTAssertEqual(grouped.count, 1, "one worker means one group")
        XCTAssertEqual(grouped[deployment.nodes[1].id], [.vaultwarden, .nextcloud])
    }

    func testAnUnknownServiceKeyDecodesInsteadOfFailing() throws {
        let json = #"{"byService":{"some-future-service":"\#(UUID().uuidString)"}}"#
        let placement = try JSONDecoder().decode(ServicePlacement.self, from: Data(json.utf8))
        XCTAssertFalse(placement.isEmpty)
        XCTAssertEqual(pair().node(running: .vaultwarden, placement: placement)?.legacySlot, .home)
    }

    func testPlacementRoundTrips() throws {
        var placement = ServicePlacement()
        let node = UUID()
        placement[.immich] = node
        let data = try JSONEncoder().encode(placement)
        let back = try JSONDecoder().decode(ServicePlacement.self, from: data)
        XCTAssertEqual(back[.immich], node)
    }
}
