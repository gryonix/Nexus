import ServerControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

@MainActor
final class TailscaleAccountDevicesTests: XCTestCase {
    private func model(_ services: Set<ServiceID>) -> DashboardViewModel {
        DashboardViewModel(deployment: Deployment(
            name: "home", topology: .singleHost, domain: "example.net",
            entry: HostEndpoint(host: "203.0.113.10", user: "root"), services: services))
    }

    func testANodeAloneListsItsDevicesInTheTailscaleAccount() {
        XCTAssertTrue(model([.tailscaleNode]).usesTailscaleAccount)
        XCTAssertFalse(model([.tailscaleNode]).managesMesh)
    }

    func testOurOwnControlServerKeepsItsOwnDeviceList() {
        XCTAssertFalse(model([.headscale, .tailscaleNode]).usesTailscaleAccount)
        XCTAssertFalse(model([.vaultwarden]).usesTailscaleAccount)
    }
}
