import XCTest
@testable import VPNProfile
import ServiceCatalog

final class ConfigurationHandoffTests: XCTestCase {
    private let wgQuick = """
    [Interface]
    PrivateKey = mInDaw06K0NgfULRObHJjkWD3ahUC8XC1tVjIf6W+Vo=
    Address = 10.9.0.4/32

    [Peer]
    PublicKey = JRI8Xc0zKP9kXk8qP84NdUQA04h6DLfFbwJn4g+/PFs=
    Endpoint = vpn.example.com:51820
    AllowedIPs = 0.0.0.0/0
    """

    private func route(_ id: ServiceID, _ text: String,
                       _ platform: VPNConfigurationProfile.Platform = .iOS) -> ConfigurationHandoff {
        VPNConfigurationHandoff.route(protocolID: id, text: text, platform: platform)
    }

    // MARK: - The tunnel protocols

    func testWireGuardIsInstalledAsAProfile() {
        XCTAssertEqual(route(.wireguardVPN, wgQuick), .configurationProfile)
        XCTAssertEqual(route(.wireguardVPN, wgQuick, .macOS), .configurationProfile)
    }

    func testAmneziaWGIsAProfileOnlyWhereItsAppExists() {
        XCTAssertEqual(route(.amneziaWG, wgQuick), .configurationProfile)
        XCTAssertEqual(route(.amneziaWG, wgQuick, .macOS), .fileOnly)
    }

    // MARK: - The proxy protocols

    /// Shadowsocks and Xray hand out a LINK, not a file
    func testShadowsocksAndXrayAreOpenedAsLinks() throws {
        let ss = "ss://YWVzLTI1Ni1nY206c2VjcmV0@vpn.example.com:8388#phone\n"
        XCTAssertEqual(route(.shadowsocks, ss),
                       .openIn(try XCTUnwrap(URL(string: "ss://YWVzLTI1Ni1nY206c2VjcmV0@vpn.example.com:8388#phone"))))

        let vless = "vless://5f1c-uuid@vpn.example.com:8443?encryption=none&security=reality#phone\n"
        XCTAssertEqual(route(.xrayReality, vless),
                       .openIn(try XCTUnwrap(URL(string: "vless://5f1c-uuid@vpn.example.com:8443?encryption=none&security=reality#phone"))))
    }

    func testALabelWithSpacesOrCyrillicIsStillOpenable() throws {
        let link = "ss://YWVzOnB3@vpn.example.com:8388#iPhone Марины"
        guard case .openIn(let url) = route(.shadowsocks, link) else {
            return XCTFail("a name with a space must not cost the link")
        }
        XCTAssertEqual(url.scheme, "ss")
        XCTAssertEqual(url.host, "vpn.example.com")
        XCTAssertEqual(url.port, 8388)
        XCTAssertEqual(url.user, "YWVzOnB3", "the credential half must survive untouched")
        XCTAssertEqual(url.fragment(percentEncoded: false), "iPhone Марины")
    }

    func testTextThatIsNotALinkFallsBackToTheFile() {
        XCTAssertEqual(route(.shadowsocks, "this is not a link"), .fileOnly)
        XCTAssertEqual(route(.shadowsocks, ""), .fileOnly)
        XCTAssertEqual(route(.xrayReality, "ss://YWVzOnB3@vpn.example.com:8388#p"), .fileOnly)
    }

    func testTheLinkIsFoundAmongOtherLines() {
        guard case .openIn(let url) = route(.shadowsocks, "# exported by the panel\n\nss://YWVzOnB3@h:8388#p\n") else {
            return XCTFail("the link line was not found")
        }
        XCTAssertEqual(url.absoluteString, "ss://YWVzOnB3@h:8388#p")
    }

    // MARK: - OpenVPN

    private let ovpn = """
    client
    dev tun
    remote vpn.example.com 1194
    """

    func testOpenVPNBecomesAProfileOnIOS() {
        XCTAssertEqual(route(.openVPN, ovpn), .configurationProfile)
    }

    func testOpenVPNIsFileOnlyOnMac() {
        XCTAssertEqual(route(.openVPN, ovpn, .macOS), .fileOnly)
    }

    func testAnOvpnThatCannotBeTakenApartStaysAFile() {
        // No `remote`: nothing to connect to.
        XCTAssertEqual(route(.openVPN, "client\ndev tun"), .fileOnly)
        // An unterminated inline block — a truncated download.
        XCTAssertEqual(route(.openVPN, "remote h 1194\n<ca>\n-----BEGIN"), .fileOnly)
    }
}
