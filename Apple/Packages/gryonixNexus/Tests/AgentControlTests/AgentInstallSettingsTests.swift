import ServiceCatalog
import XCTest
@testable import AgentControl

/// The app's half of the settings contract with `install::execute::build_input`
final class AgentInstallSettingsTests: XCTestCase {
    func testEveryDeclaredKeyIsProducedAndNothingElseIs() {
        let produced = Set(AgentInstallSettings.map(from: ServiceSettings()).keys)
        XCTAssertEqual(produced, AgentInstallSettings.keys)
        XCTAssertFalse(produced.contains(AgentInstallSettings.vpnProtocolsKey),
                       "vpn_protocols says WHAT to install, not how — it rides on the request")
    }

    func testMovedPathsTravelForServicesThatAreNotBeingInstalled() {
        var settings = ServiceSettings()
        settings.nextcloudPath = "/srv/nextcloud"
        settings.jellyfinMediaPath = "/mnt/films"
        settings.xrayRealitySNI = "www.cloudflare.com"
        let map = AgentInstallSettings.map(from: settings)
        XCTAssertEqual(map["nextcloud_path"], "/srv/nextcloud")
        XCTAssertEqual(map["jellyfin_media_path"], "/mnt/films")
        XCTAssertEqual(map["xray_reality_sni"], "www.cloudflare.com")
    }

    func testFlagsAndPortsAreSentInTheFormTheAgentParses() {
        var settings = ServiceSettings()
        settings.vaultwardenAllowSignups = false
        settings.xrayRealityPort = 9443
        settings.forgejoSSHPort = 0
        let map = AgentInstallSettings.map(from: settings)
        XCTAssertEqual(map["vaultwarden_allow_signups"], "false")
        XCTAssertEqual(map["xray_reality_port"], "9443")
        XCTAssertEqual(map["forgejo_ssh_port"], "0")
    }

    func testAddingAProtocolKeepsTheOnesAlreadyInstalled() {
        let installed: Set<ServiceID> = [.wireguardVPN, .vpnPanel, .nextcloud]
        let value = AgentInstallSettings.vpnProtocolList(adding: .openVPN, installed: installed)
        XCTAssertEqual(value, "wireguard-vpn,openvpn")
    }

    func testTheListFollowsTheCatalogsOrder() {
        let installed: Set<ServiceID> = [.openVPN, .shadowsocks]
        let value = AgentInstallSettings.vpnProtocolList(adding: .wireguardVPN, installed: installed)
        XCTAssertEqual(value, "wireguard-vpn,shadowsocks,openvpn")
    }

    func testANonVPNServiceGetsNoProtocolList() {
        XCTAssertNil(AgentInstallSettings.vpnProtocolList(adding: .nextcloud, installed: [.wireguardVPN]))
        XCTAssertNil(AgentInstallSettings.vpnProtocolList(adding: .jellyfin, installed: []))
    }
}
