import ServiceCatalog
import XCTest
@testable import ServerControl

final class VPNPlacementTests: XCTestCase {
    private func pair(vpnOnRelay: Bool? = nil) -> Deployment {
        var deployment = Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.com",
                                    entry: HostEndpoint(host: "203.0.113.10", port: 2222, user: "admin"),
                                    homeWGAddress: "10.8.0.2",
                                    services: [.wireguardVPN, .xrayReality, .vpnPanel, .nextcloud],
                                    usesAgent: true)
        deployment.vpnOnRelay = vpnOnRelay
        return deployment
    }

    func testAtHomeTheVPNRunsWithEverythingElse() {
        let deployment = pair()
        XCTAssertFalse(deployment.vpnRunsOnRelay)
        XCTAssertEqual(deployment.vpnHost, deployment.servicesHost)
        XCTAssertEqual(deployment.otherVPNHost, deployment.relayNode?.sshHost)
        XCTAssertEqual(deployment.host(running: .wireguardVPN), deployment.servicesHost)
        XCTAssertEqual(Set(deployment.servicesBehindRelay.map(\.id)), Set(deployment.installedServices.map(\.id)))
    }

    func testOnTheRelayOnlyTheVPNFamilyMoves() {
        let deployment = pair(vpnOnRelay: true)
        let relay = deployment.relayNode?.sshHost
        XCTAssertTrue(deployment.vpnRunsOnRelay)
        XCTAssertEqual(deployment.vpnHost, relay)
        XCTAssertEqual(deployment.otherVPNHost, deployment.servicesHost)
        for service in [ServiceID.wireguardVPN, .xrayReality, .vpnPanel] {
            XCTAssertEqual(deployment.host(running: service), relay, service.rawValue)
        }
        XCTAssertEqual(deployment.host(running: .nextcloud), deployment.servicesHost)
        XCTAssertEqual(deployment.servicesBehindRelay.map(\.id), [.nextcloud])
    }

    func testOneMachineNeverRunsTheVPNOnARelay() {
        var deployment = Deployment(name: "A", topology: .singleHost, domain: "example.com",
                                    entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                                    services: [.wireguardVPN], usesAgent: true)
        deployment.vpnOnRelay = true
        XCTAssertNil(deployment.relayNode)
        XCTAssertFalse(deployment.canRunVPNOnRelay)
        XCTAssertFalse(deployment.vpnRunsOnRelay)
        XCTAssertEqual(deployment.vpnHost, deployment.servicesHost)
        XCTAssertNil(deployment.otherVPNHost)
    }

    func testTheStateDirectoriesFollowTheInstalledProtocols() {
        var deployment = pair()
        deployment.serviceSettings.xrayRealityPath = "/opt/xray"
        XCTAssertEqual(deployment.vpnStateDirectories, [VPNPanelService.path, "/opt/xray"])
    }

    func testTheFlagSurvivesSavingAndOldFilesReadAsHome() throws {
        let moved = pair().movingVPN(toRelay: true)
        let decoded = try JSONDecoder().decode(Deployment.self, from: JSONEncoder().encode(moved))
        XCTAssertTrue(decoded.vpnRunsOnRelay)
        let back = moved.movingVPN(toRelay: false)
        XCTAssertNil(back.vpnOnRelay)
        let old = try JSONDecoder().decode(Deployment.self, from: JSONEncoder().encode(pair()))
        XCTAssertNil(old.vpnOnRelay)
    }
}
