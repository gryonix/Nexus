import XCTest
@testable import ServiceCatalog

final class ForwardedPortsTests: XCTestCase {
    private func context(domain: String = "example.com") -> ServiceContext {
        ServiceContext(domain: domain, sshUser: "admin")
    }

    func testTheLivePairsPortSetIsWhatTheDerivationProduces() {
        let services = ServiceRegistry.services([.dockerMailserver, .nextcloud, .vaultwarden, .vpnPanel])
        XCTAssertEqual(ForwardedPorts.tcp(services: services, context: context()),
                       [25, 80, 143, 443, 465, 587, 993, 4190])
    }

    func testHTTPIsAlwaysThereAndHTTPSFollowsAWebService() {
        XCTAssertEqual(ForwardedPorts.tcp(services: [], context: context()), [80])
        let web = ServiceRegistry.services([.vaultwarden])
        XCTAssertEqual(ForwardedPorts.tcp(services: web, context: context()), [80, 443])
    }

    func testUDPIsOnlyWhatTheServicesDeclare() {
        XCTAssertEqual(ForwardedPorts.udp(services: ServiceRegistry.services([.vaultwarden]),
                                          context: context()),
                       [])
        var settings = ServiceSettings()
        settings.wireguardVPNPort = 51821
        let withVPN = ServiceContext(domain: "example.com", sshUser: "admin", settings: settings)
        XCTAssertEqual(ForwardedPorts.udp(services: ServiceRegistry.services([.wireguardVPN]),
                                          context: withVPN),
                       [51821])
    }

    func testTheDerivationIsSortedAndDeduplicated() {
        let services = ServiceRegistry.services([.dockerMailserver, .nextcloud, .vaultwarden])
        let ports = ForwardedPorts.tcp(services: services, context: context())
        XCTAssertEqual(ports, ports.sorted(), "the rules read better in order, and fixtures depend on it")
        XCTAssertEqual(ports.count, Set(ports).count, "two services on one port must produce one rule")
    }
}
