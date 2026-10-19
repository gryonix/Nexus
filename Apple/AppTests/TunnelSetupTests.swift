import ServerControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

final class TunnelSetupTests: XCTestCase {
    private func deployment(_ services: Set<ServiceID>) -> Deployment {
        var deployment = Deployment(name: "tunnel", topology: .singleHost, domain: "example.test",
                                    entry: HostEndpoint(host: "192.168.1.20", user: "root"))
        deployment.services = services
        return deployment
    }

    func testTheMailHostKeepsItsOwnRecords() {
        let web: Set<ServiceID> = [.cloudflared, .vaultwarden, .jellyfin]
        let names = TunnelSetup.webNames(of: deployment(web.union([.mailcow])))

        XCTAssertFalse(names.contains { $0.hasPrefix("mail.") }, "\(names)")
        XCTAssertEqual(names, TunnelSetup.webNames(of: deployment(web)))
        XCTAssertFalse(names.isEmpty)
    }
}
