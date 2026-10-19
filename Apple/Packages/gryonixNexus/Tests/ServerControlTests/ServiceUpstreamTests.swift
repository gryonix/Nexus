import ServiceCatalog
import XCTest
@testable import ServerControl

final class ServiceUpstreamTests: XCTestCase {
    private func single(_ services: Set<ServiceID> = [.vaultwarden]) -> Deployment {
        Deployment(name: "A", topology: .singleHost, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"), services: services)
    }

    private func pair(_ services: Set<ServiceID> = [.vaultwarden]) -> Deployment {
        Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                   homeWGAddress: "10.8.0.2", services: services)
    }

    func testASingleHostServesItsOwnServicesWithNoHop() {
        XCTAssertEqual(single().upstream(for: .vaultwarden, siteName: "vault.example.com"), .local)
    }

    /// The load-bearing test of this step
    func testScenarioBStaysLocalEvenAfterAMeshIsInstalled() {
        XCTAssertEqual(pair().upstream(for: .vaultwarden, siteName: "vault.example.com"), .local)

        let withMesh = pair([.vaultwarden, .headscale, .tailscaleNode])
        XCTAssertEqual(withMesh.upstream(for: .vaultwarden, siteName: "vault.example.com"), .local,
                       "a mesh appearing in the catalog must not change how a working pair is served")
    }

    private func hubAndSpoke(_ services: Set<ServiceID>) -> (Deployment, DeploymentNode) {
        let seed = single(services)
        let ingress = seed.derivedNodes[0]
        let spoke = DeploymentNode(id: UUID(),
                                   name: "workshop",
                                   endpoint: HostEndpoint(host: "192.168.1.50", user: "root"),
                                   capabilities: [.worker],
                                   routedThrough: ingress.id,
                                   servesOwnTraffic: false)
        var deployment = seed
        deployment.storedNodes = [ingress, spoke]
        return (deployment, spoke)
    }

    func testAProxiedWorkerIsReachedOverTheMeshWithAnExplicitServerName() {
        let (deployment, spoke) = hubAndSpoke([.vaultwarden, .headscale])
        var placement = ServicePlacement()
        placement[.vaultwarden] = spoke.id

        XCTAssertEqual(deployment.upstream(for: .vaultwarden,
                                           siteName: "vault.example.com",
                                           placement: placement),
                       .mesh(nodeID: spoke.id, serverName: "vault.example.com"))
    }

    func testAProxiedWorkerWithoutAMeshIsReportedAsUnroutable() {
        let (deployment, spoke) = hubAndSpoke([.vaultwarden])
        var placement = ServicePlacement()
        placement[.vaultwarden] = spoke.id

        XCTAssertEqual(deployment.placementProblems(placement), [.needsMeshToReachWorker(.vaultwarden)])
    }

    func testAServiceLeftOnTheHubIsStillServedLocally() {
        let (deployment, _) = hubAndSpoke([.vaultwarden, .headscale])
        XCTAssertEqual(deployment.upstream(for: .vaultwarden, siteName: "vault.example.com"), .local)
    }

    func testTodaysDeploymentsHaveNoPlacementProblems() {
        XCTAssertTrue(single().placementProblems().isEmpty)
        XCTAssertTrue(pair().placementProblems().isEmpty)
        XCTAssertTrue(pair([.vaultwarden, .nextcloud, .mailcow]).placementProblems().isEmpty)
    }
}
