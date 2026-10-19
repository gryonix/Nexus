import XCTest
@testable import ServiceCatalog

final class HostnamePinningTests: XCTestCase {
    func testAnInstalledSiblingKeepsTheSharedName() {
        let pinned = ServiceDefaultHostnames.pinningSiblings(
            adding: .psono, to: ServiceSettings(), installed: [.vaultwarden, .nextcloud], domain: "example.com")
        XCTAssertEqual(pinned.vaultwardenHostname, "vault.example.com")
        XCTAssertEqual(pinned.psonoHostname, "", "the newcomer takes its own name")
        XCTAssertEqual(pinned.nextcloudHostname, "", "other groups are untouched")
    }

    func testANameAlreadyChosenAndALoneServiceStayAsTheyAre() {
        var settings = ServiceSettings()
        settings.vaultwardenHostname = "pw.example.com"
        XCTAssertEqual(ServiceDefaultHostnames.pinningSiblings(
            adding: .psono, to: settings, installed: [.vaultwarden], domain: "example.com").vaultwardenHostname,
                       "pw.example.com")
        XCTAssertEqual(ServiceDefaultHostnames.pinningSiblings(
            adding: .jellyfin, to: ServiceSettings(), installed: [.vaultwarden], domain: "example.com"),
                       ServiceSettings())
    }
}
