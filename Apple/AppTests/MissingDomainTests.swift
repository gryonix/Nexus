import ServerControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

@MainActor
final class MissingDomainTests: XCTestCase {
    private func deployment(domain: String) -> Deployment {
        Deployment(name: "adopted",
                   topology: .singleHost,
                   domain: domain,
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                   services: [.mailcow, .vaultwarden, .nextcloud])
    }

    func testAnEmptyDomainProducesNoOpenableSites() {
        let model = DashboardViewModel(deployment: deployment(domain: ""))
        XCTAssertTrue(model.webSites.isEmpty,
                      "a host ending in a bare dot is not an address: \(model.webSites.map(\.host))")
        XCTAssertTrue(model.sitesNeedDomain,
                      "the screen has to be able to say why the list is empty")
    }

    func testARealDomainStillListsEveryService() {
        let model = DashboardViewModel(deployment: deployment(domain: "example.net"))
        XCTAssertFalse(model.webSites.isEmpty)
        XCTAssertFalse(model.sitesNeedDomain, "nothing is missing here")
        for site in model.webSites {
            XCTAssertTrue(site.host.hasSuffix(".example.net"), site.host)
            XCTAssertNotNil(site.url)
        }
    }

    func testAServerWithNoWebFacesIsNotMissingADomain() {
        var bare = deployment(domain: "")
        bare.services = [.wireguardVPN]
        let model = DashboardViewModel(deployment: bare)
        XCTAssertTrue(model.webSites.isEmpty)
        XCTAssertFalse(model.sitesNeedDomain,
                       "no site wanted a domain, so none is missing")
    }

    func testTheDNSExportIsEmptyWithoutADomainAndWholeWithOne() {
        XCTAssertTrue(ConfigurationExport.build(for: deployment(domain: "")).dns.isEmpty)
        XCTAssertFalse(ConfigurationExport.build(for: deployment(domain: "example.net")).dns.isEmpty,
                       "with a domain the records must come back — otherwise the message is right for the wrong reason")
    }
}
