import ServerControl
import ServiceCatalog
import XCTest
@testable import gryonixNexus

final class ServiceDNSPublisherTests: XCTestCase {
    private func server(_ host: String) -> Deployment {
        Deployment(name: "pair", topology: .singleHost, domain: "example.test",
                   entry: HostEndpoint(host: host, user: "root"))
    }

    func testAnAddressEnteredAsDigitsIsUsedAsIs() async {
        let ip = await ServiceDNSPublisher.address(of: server("203.0.113.40")) { _ in ["198.51.100.1"] }
        XCTAssertEqual(ip, "203.0.113.40")
    }

    func testAServerEnteredByNameGetsTheAddressThatNameHas() async {
        let ip = await ServiceDNSPublisher.address(of: server("vps.example.test")) { name in
            name == "vps.example.test" ? ["203.0.113.50"] : []
        }
        XCTAssertEqual(ip, "203.0.113.50")
    }

    func testANameThatDoesNotResolveGivesNoAddress() async {
        let ip = await ServiceDNSPublisher.address(of: server("vps.example.test")) { _ in [] }
        XCTAssertNil(ip)
    }

    private func vaultServer(_ services: Set<ServiceID> = [.vaultwarden]) -> Deployment {
        Deployment(name: "pair", topology: .singleHost, domain: "example.test",
                   entry: HostEndpoint(host: "203.0.113.40", user: "root"), services: services)
    }

    func testAnAddedServiceWithoutItsRecordAsksToAddIt() async throws {
        let vault = try XCTUnwrap(ServiceRegistry.service(.vaultwarden))
        let (update, notes) = await ServiceDNSPublisher.pending(adding: vault, to: vaultServer()) { _ in [] }
        XCTAssertEqual(update?.add, ["vault.example.test"])
        XCTAssertEqual(update?.remove, [])
        XCTAssertTrue(notes.isEmpty)
    }

    func testAnAddedServiceWhoseRecordIsInPlaceAsksNothing() async throws {
        let vault = try XCTUnwrap(ServiceRegistry.service(.vaultwarden))
        let (update, _) = await ServiceDNSPublisher.pending(adding: vault, to: vaultServer()) { _ in ["203.0.113.40"] }
        XCTAssertNil(update)
    }

    func testARemovedServiceAsksToRemoveTheRecordStillPointingHere() async throws {
        let vault = try XCTUnwrap(ServiceRegistry.service(.vaultwarden))
        let update = await ServiceDNSPublisher.pending(removing: vault, from: vaultServer(), keeping: vaultServer([])) { _ in
            ["203.0.113.40"]
        }
        XCTAssertEqual(update?.remove, ["vault.example.test"])
        let gone = await ServiceDNSPublisher.pending(removing: vault, from: vaultServer(), keeping: vaultServer([])) { _ in [] }
        XCTAssertNil(gone, "nothing to remove when the name points nowhere")
    }
}
