import AgentClient
import AgentControl
import ServerControl
import ServiceCatalog
import XCTest
@testable import gryonixNexus

@MainActor
final class VPNRelayTests: XCTestCase {
    private func pair(vpnOnRelay: Bool? = nil) -> Deployment {
        var deployment = Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.com",
                                    entry: HostEndpoint(host: "203.0.113.10", port: 2222, user: "admin"),
                                    homeWGAddress: "10.8.0.2",
                                    services: [.wireguardVPN, .shadowsocks, .vpnPanel, .nextcloud],
                                    usesAgent: true)
        deployment.vpnOnRelay = vpnOnRelay
        return deployment
    }

    private func forwardedUDP(_ deployment: Deployment) -> Set<UInt32> {
        Set(DashboardViewModel.hostSurface(for: deployment, role: .vpsRelay, devicePublicKey: "").relayForwardedUDPPorts)
    }

    func testTheRelayStopsSendingVPNPortsHomeOnceTheVPNMoves() {
        let wireGuard = UInt32(pair().serviceSettings.wireguardVPNPort)
        XCTAssertTrue(forwardedUDP(pair()).contains(wireGuard))
        XCTAssertFalse(forwardedUDP(pair(vpnOnRelay: true)).contains(wireGuard))
        XCTAssertNotEqual(DashboardViewModel.forwardedPorts(of: pair()),
                          DashboardViewModel.forwardedPorts(of: pair(vpnOnRelay: true)))
    }

    func testAPlanSplitsOnlyWhenTheVPNIsOnTheRelay() {
        let services = [ServiceID.wireguardVPN, .nextcloud].compactMap(ServiceRegistry.service)
        let steps = ServiceInstallPlan.steps(for: services, installed: [])
        let home = DashboardViewModel.splitForRelay(steps, vpnOnRelay: false)
        XCTAssertTrue(home.vpn.isEmpty)
        XCTAssertEqual(home.rest.count, steps.count)
        let relay = DashboardViewModel.splitForRelay(steps, vpnOnRelay: true)
        XCTAssertEqual(relay.vpn.map(\.service.id), [.wireguardVPN])
        XCTAssertEqual(relay.rest.map(\.service.id), [.nextcloud])
    }

    func testRelayInstallsCarryTheRelayRole() {
        let onRelay = DashboardViewModel(deployment: pair(vpnOnRelay: true))
        XCTAssertEqual(onRelay.surfaceRole(for: .shadowsocks), .vpsRelay)
        XCTAssertNil(onRelay.surfaceRole(for: .nextcloud))
        XCTAssertNil(DashboardViewModel(deployment: pair()).surfaceRole(for: .shadowsocks))
    }

    func testTheHomeResolverIsOfferedWhileTheVPNIsOnTheRelay() {
        var deployment = pair(vpnOnRelay: true)
        deployment.services.insert(.adguardHome)
        let model = DashboardViewModel(deployment: deployment)
        let answered = model.withHomeResolvers(VPNDNSDefaults(dns: [], localAddress: "10.53.0.53"))
        XCTAssertEqual(answered.localServices, [.adguardHome])
        let atHome = DashboardViewModel(deployment: pair()).withHomeResolvers(VPNDNSDefaults(localAddress: "10.53.0.53"))
        XCTAssertTrue(atHome.localServices.isEmpty)
    }

    func testTheDNSOrderIsEditedWithinItsBounds() {
        typealias Edit = VPNDNSPriorityEditing
        let order = ["local", "1.1.1.1", "9.9.9.9"]
        XCTAssertEqual(Edit.moveUp(1, in: order), ["1.1.1.1", "local", "9.9.9.9"])
        XCTAssertEqual(Edit.moveUp(0, in: order), order)
        XCTAssertEqual(Edit.moveDown(2, in: order), order)
        XCTAssertEqual(Edit.remove(0, from: order), ["1.1.1.1", "9.9.9.9"])
        XCTAssertEqual(Edit.remove(0, from: ["local"]), ["local"], "the last resolver stays")
        XCTAssertEqual(Edit.add("8.8.8.8", to: order), order + ["8.8.8.8"])
        XCTAssertEqual(Edit.add("1.1.1.1", to: order), order, "no repeats")
        let full = order + ["8.8.8.8"]
        XCTAssertEqual(Edit.add("1.0.0.1", to: full), full, "four at most")
        XCTAssertFalse(Edit.canAdd(to: full))
    }

    func testEntriesAreNamedForPeople() {
        let local = LocalDNS(address: "10.53.0.53", services: [.adguardHome])
        XCTAssertEqual(VPNDNSPriorityEditing.name(of: "local", local: local), local.name)
        XCTAssertTrue(VPNDNSPriorityEditing.name(of: "1.1.1.1", local: local).contains("Cloudflare"))
        XCTAssertEqual(VPNDNSPriorityEditing.name(of: "203.0.113.53", local: local), "203.0.113.53")
    }

    func testARefusedPanelIsTheVPNRunningOnTheOtherMachine() {
        let refused = AgentError.rpc(code: "internal",
                                     message: "the VPN panel could not do that: Connection refused (os error 111)")
        XCTAssertTrue(DashboardViewModel.panelIsAbsent(refused))
        let other = AgentError.rpc(code: "internal", message: "the VPN panel could not do that: HTTP 500")
        XCTAssertFalse(DashboardViewModel.panelIsAbsent(other), "a panel that answered is where the VPN is")
    }
}
