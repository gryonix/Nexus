import AgentControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

/// This server's own resolver in the DNS choice
final class LocalDNSTests: XCTestCase {
    private let address = "10.53.0.53"

    func testItIsOfferedOnlyWithAnAddressAndAResolver() {
        XCTAssertTrue(LocalDNS(address: address, services: [.pihole]).isOffered)
        XCTAssertFalse(LocalDNS(address: address).isOffered)
        XCTAssertFalse(LocalDNS(address: "", services: [.pihole]).isOffered)
    }

    func testADeviceOnTheAddressIsNamedAfterTheResolverOnTheServer() {
        let local = LocalDNS(VPNDNSDefaults(dns: [address], localAddress: address, localServices: [.adguardHome]))
        XCTAssertTrue(local.isChosen([address]))
        XCTAssertEqual(local.name(for: [address]), "AdGuard Home (your server)")
        XCTAssertFalse(local.isChosen(["1.1.1.1", address]))
        XCTAssertEqual(local.name(for: ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001"]),
                       "Cloudflare (public)")
    }

    func testBothResolversShareOneServerName() {
        let local = LocalDNS(address: address, services: [.adguardHome, .pihole])
        XCTAssertEqual(local.name, "AdGuard Home / Pi-hole (your server)")
    }

    func testThePublicAdGuardServiceIsNotTakenForTheServersOwn() {
        let adguard = PublicDNS.all.first { $0.id == "adguard" }!.addresses
        let local = LocalDNS(address: address, services: [.adguardHome])
        XCTAssertEqual(local.name(for: adguard), "AdGuard DNS (public)")
        XCTAssertNotEqual(local.name(for: adguard), local.name(for: [address]))
    }

    func testTheServersAddressIsNamedBeforeTheServerAnswers() {
        XCTAssertEqual(LocalDNS().name(for: [LocalDNS.serverAddress]), "This server's DNS")
        XCTAssertEqual(LocalDNS().name(for: ["203.0.113.53"]), "203.0.113.53")
        XCTAssertEqual(LocalDNS().name(for: []), "Cloudflare (public)")
    }

    func testARemovedResolverIsReportedGone() {
        let removed = LocalDNS(address: address)
        XCTAssertTrue(removed.isGone([address]))
        XCTAssertFalse(removed.isGone(["1.1.1.1"]))
        XCTAssertFalse(LocalDNS(address: address, services: [.adguardHome]).isGone([address]))
        XCTAssertFalse(LocalDNS().isChosen([]))
    }

    func testAServerResolverIsRememberedForAnUnreachableServer() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "LocalDNSTests"))
        defaults.removePersistentDomain(forName: "LocalDNSTests")
        let server = UUID()
        XCTAssertNil(LocalDNSMemory.recall(server, in: defaults))
        LocalDNSMemory.keep(LocalDNS(address: address), for: server, in: defaults)
        XCTAssertNil(LocalDNSMemory.recall(server, in: defaults))
        LocalDNSMemory.keep(LocalDNS(address: address, services: [.adguardHome]), for: server, in: defaults)
        XCTAssertEqual(LocalDNSMemory.recall(server, in: defaults), LocalDNS(address: address, services: [.adguardHome]))
    }

    func testTheDNSMenuRedrawsOnlyWhenItsChoiceChanges() {
        let owner = UUID()
        let menu = VPNDNSMenu(title: "DNS", addresses: [address], owner: owner) { _ in }
        XCTAssertEqual(menu, VPNDNSMenu(title: "DNS", addresses: [address], owner: owner) { _ in })
        XCTAssertNotEqual(menu, VPNDNSMenu(title: "DNS", addresses: ["1.1.1.1"], owner: owner) { _ in })
        XCTAssertNotEqual(menu, VPNDNSMenu(title: "DNS", addresses: [address], owner: UUID()) { _ in })
    }
}
