import ServiceCatalog
import XCTest
@testable import gryonixNexus

final class ServiceInstallPlanTests: XCTestCase {
    private func services(_ ids: [ServiceID]) -> [any ManagedService] {
        ids.compactMap(ServiceRegistry.service)
    }

    func testNewVPNProtocolsGoToTheServerTogether() {
        let steps = ServiceInstallPlan.steps(for: services([.amneziaWG, .vaultwarden, .xrayReality]),
                                             installed: [])
        XCTAssertEqual(steps.map(\.service.id), [.amneziaWG, .vaultwarden])
        XCTAssertEqual(steps.first?.alsoProtocols, [.xrayReality])
        XCTAssertEqual(steps.last?.alsoProtocols, [])
    }

    func testOnlyWhatIsNotInstalledIsPlanned() {
        let steps = ServiceInstallPlan.steps(for: services([.amneziaWG, .xrayReality, .vaultwarden]),
                                             installed: [.amneziaWG, .vaultwarden])
        XCTAssertEqual(steps.map(\.service.id), [.xrayReality])
        XCTAssertEqual(steps.first?.alsoProtocols, [])
    }

    func testAServiceChosenTwiceIsPlannedOnce() {
        let steps = ServiceInstallPlan.steps(for: services([.vaultwarden, .vaultwarden]), installed: [])
        XCTAssertEqual(steps.count, 1)
    }

    func testSetupSendsTheVPNOnceAndSkipsWhatTheHostRuns() {
        let chosen = services([.vpnPanel, .wireguardVPN, .amneziaWG, .xrayReality, .vaultwarden])
        let run = ServiceInstallPlan.agentRun(chosen: chosen, onHost: [.wireguardVPN, .vaultwarden])
        XCTAssertEqual(run.map(\.id), [.wireguardVPN])
    }

    func testSetupLeavesARunningVPNAlone() {
        let chosen = services([.vpnPanel, .wireguardVPN, .amneziaWG])
        let run = ServiceInstallPlan.agentRun(chosen: chosen, onHost: [.wireguardVPN, .amneziaWG])
        XCTAssertTrue(run.isEmpty)
    }

    func testRemovingOneVPNProtocolKeepsTheOthersAndThePanel() throws {
        let xray = try XCTUnwrap(ServiceRegistry.service(.xrayReality))
        let installed: Set<ServiceID> = [.wireguardVPN, .xrayReality, .vpnPanel]
        XCTAssertEqual(DashboardViewModel.remainingVPNProtocols(after: xray, in: installed), [.wireguardVPN])
        XCTAssertEqual(DashboardViewModel.removedServices(with: xray, installed: installed), [.xrayReality])
        XCTAssertTrue(DashboardViewModel.removedServices(with: xray, installed: [.xrayReality, .vpnPanel])
            .contains(.vpnPanel))
    }

    func testARepairRunsEveryServiceAgainButLeavesTheTunnel() {
        let steps = ServiceInstallPlan.rerun(services([.nextcloud, .vpnPanel, .amneziaWG, .xrayReality, .cloudflared]))
        // The VPN step lists the installed protocols itself.
        XCTAssertEqual(steps.map(\.service.id), [.nextcloud, .amneziaWG])
    }
}
