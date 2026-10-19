import XCTest
@testable import ServiceCatalog

final class CaddySetupGuardTests: XCTestCase {
    private let site = "photos.example.com {\n    # gryonixnexus: immich\n    import /etc/caddy/gryonixnexus-admin-guard\n    reverse_proxy 127.0.0.1:2283\n}"

    func testAFirstVisitorSiteWaitsBehindTheVPNOnlyWithWireGuard() {
        let guarded = CaddySetupGuard.guarding(site, owner: "immich", installed: [.immich, .wireguardVPN])
        XCTAssertTrue(guarded.contains("    import /etc/caddy/gryonixnexus-setup/immich*\n    import /etc/caddy/gryonixnexus-admin-guard"))
        XCTAssertEqual(CaddySetupGuard.guarding(site, owner: "immich", installed: [.immich]), site)
        XCTAssertEqual(CaddySetupGuard.guarding(site, owner: "vaultwarden", installed: [.wireguardVPN]), site)
    }

    func testTheRulesMatchTheAgentsByteForByte() {
        let expected = "@gryonixnexus_setup_relay {\n    remote_ip 10.8.0.0/24\n    not remote_ip 10.8.0.254/32\n}\nrespond @gryonixnexus_setup_relay \"This site opens to the internet once its first account exists. Connect to your WireGuard VPN to create it.\" 403\n@gryonixnexus_setup_public not remote_ip private_ranges\nrespond @gryonixnexus_setup_public \"This site opens to the internet once its first account exists. Connect to your WireGuard VPN to create it.\" 403\n@gryonixnexus_setup_tunnel header Cf-Connecting-IP *\nrespond @gryonixnexus_setup_tunnel \"This site opens to the internet once its first account exists. Connect to your WireGuard VPN to create it.\" 403\n"
        XCTAssertEqual(CaddySetupGuard.rules, expected)
    }

    func testTheGuardIsArmedOnlyForASiteTheHostDoesNotServeYet() {
        let section = CaddySetupGuard.armSection(["n8n"])
        XCTAssertTrue(section.hasPrefix("\nif ! grep -qE '^[[:space:]]*# gryonixnexus: n8n$' /etc/caddy/Caddyfile"))
        XCTAssertTrue(section.contains("<<'EOF_SETUP_GUARD'\n@gryonixnexus_setup_relay {"))
        XCTAssertTrue(section.contains("403\nEOF_SETUP_GUARD\n"))
        XCTAssertEqual(CaddySetupGuard.armSection([]), "")
    }
}
