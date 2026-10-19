import ServiceCatalog
import XCTest
@testable import VPNProfile
@testable import VPNTunnel

final class PanelConfigGoldenTests: XCTestCase {
    private struct Case: Decodable {
        let name: String
        let `protocol`: String
        let text: String
    }

    private struct Golden: Decodable {
        let cases: [Case]
        let note: String
    }

    private func golden() throws -> Golden {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "panel-vpn-configs",
                                                  withExtension: "json"),
                                "the golden is not bundled with this test target")
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    private func serviceID(_ raw: String) throws -> ServiceID {
        switch raw {
        case "wireguard": return .wireguardVPN
        case "amneziawg": return .amneziaWG
        case "shadowsocks": return .shadowsocks
        case "xray": return .xrayReality
        default:
            throw XCTSkip("the golden names a protocol this test does not map: \(raw)")
        }
    }

    func testTheGoldenCarriesTheSixConfigsItWasDumpedFor() throws {
        let cases = try golden().cases
        XCTAssertEqual(cases.count, 6)
        XCTAssertEqual(Set(cases.map(\.name)),
                       ["wireguard-first-client",
                        "wireguard-second-client",
                        "amneziawg-first-client",
                        "shadowsocks-first-client",
                        "shadowsocks-name-with-a-space",
                        "xray-first-client"])
    }

    private var interfaceShaped: [String] { ["wireguard", "amneziawg"] }

    func testEveryPanelConfigBecomesAProfile() throws {
        for entry in try golden().cases where interfaceShaped.contains(entry.protocol) {
            let built = try TunnelProfileBuilder.build(text: entry.text,
                                                       protocolID: try serviceID(entry.protocol),
                                                       serverID: UUID(),
                                                       serverName: "vps-middle",
                                                       deviceID: entry.name,
                                                       deviceName: entry.name)
            XCTAssertFalse(built.profile.endpoint.isEmpty, entry.name)
            XCTAssertFalse(built.profile.addresses.isEmpty, entry.name)
            XCTAssertEqual(built.profile.allowedIPs, ["0.0.0.0/0"], entry.name)
            XCTAssertEqual(built.profile.mtu, 1280, entry.name)
            XCTAssertEqual(built.profile.dns, ["1.1.1.1"], entry.name)
            XCTAssertEqual(built.secret,
                           entry.text.trimmingCharacters(in: .whitespacesAndNewlines),
                           entry.name)
            XCTAssertTrue(built.secret.contains("PrivateKey"), entry.name)
        }
    }

    /// The link half, and what it deliberately does NOT claim
    func testEveryPanelLinkBecomesAProfileNamingOnlyWhatALinkKnows() throws {
        var seen = 0
        for entry in try golden().cases where !interfaceShaped.contains(entry.protocol) {
            seen += 1
            let built = try TunnelProfileBuilder.build(text: entry.text,
                                                       protocolID: try serviceID(entry.protocol),
                                                       serverID: UUID(),
                                                       serverName: "vps-middle",
                                                       deviceID: entry.name,
                                                       deviceName: entry.name)
            XCTAssertEqual(built.profile.endpoint, "vpn.example.com:\(entry.protocol == "xray" ? 8443 : 8388)",
                           entry.name)
            XCTAssertEqual(built.profile.addresses, [], entry.name)
            XCTAssertEqual(built.profile.dns, [], entry.name)
            XCTAssertNil(built.profile.mtu, entry.name)
            XCTAssertEqual(built.profile.allowedIPs, ["0.0.0.0/0", "::/0"], entry.name)
            XCTAssertEqual(built.secret,
                           entry.text.trimmingCharacters(in: .whitespacesAndNewlines),
                           entry.name)
        }
        XCTAssertEqual(seen, 3, "the link half of the golden went missing")
    }

    func testANameWithASpaceSurvivesTheLinkAndComesBackWithIt() throws {
        let entry = try XCTUnwrap(golden().cases.first { $0.name == "shadowsocks-name-with-a-space" })
        XCTAssertTrue(entry.text.contains("#work%20laptop"),
                      "the panel stopped escaping the fragment")
        let link = try ProxyLinkConfig(parsing: entry.text, kind: .shadowsocks)
        XCTAssertEqual(link.label, "work laptop")
    }

    func testTheShadowsocksCredentialIsThePairSIP022Asks() throws {
        let entry = try XCTUnwrap(golden().cases.first { $0.name == "shadowsocks-first-client" })
        let link = try ProxyLinkConfig(parsing: entry.text, kind: .shadowsocks)
        guard case .shadowsocks(let method, let password) = link.credential else {
            return XCTFail("the panel's own link did not read as Shadowsocks")
        }
        XCTAssertEqual(method, "2022-blake3-aes-256-gcm",
                       "the panel's cipher is SIP022's, not one of the older AEAD names")
        XCTAssertTrue(password.contains(":"),
                      "a SIP022 password is the server key and the user key, joined")
    }

    func testTheRealityParametersSurviveTheLink() throws {
        let entry = try XCTUnwrap(golden().cases.first { $0.protocol == "xray" })
        let link = try ProxyLinkConfig(parsing: entry.text, kind: .vless)
        guard case .vless(let vless) = link.credential else {
            return XCTFail("the panel's own link did not read as VLESS")
        }
        XCTAssertEqual(vless.security, "reality")
        XCTAssertEqual(vless.sni, "www.microsoft.com")
        XCTAssertEqual(vless.fingerprint, "chrome")
        XCTAssertEqual(vless.publicKey, "xrK4Y_1n7QkbWZ8mQ2vN9pLd")
        XCTAssertEqual(vless.shortID, "9a3f")
        XCTAssertEqual(vless.flow, "xtls-rprx-vision")
        XCTAssertEqual(vless.network, "tcp",
                       "the panel writes type=tcp, and the datapath reads it")
    }

    func testOnlyTheAmneziaConfigIsObfuscated() throws {
        for entry in try golden().cases {
            let built = try TunnelProfileBuilder.build(text: entry.text,
                                                       protocolID: try serviceID(entry.protocol),
                                                       serverID: UUID(),
                                                       serverName: "vps-middle",
                                                       deviceID: entry.name,
                                                       deviceName: entry.name)
            XCTAssertEqual(built.profile.isObfuscated,
                           entry.protocol == "amneziawg",
                           entry.name)
        }
    }

    func testTheTwoWireGuardClientsAreNotTheSameTunnel() throws {
        let wg = try golden().cases.filter { $0.protocol == "wireguard" }
        XCTAssertEqual(wg.count, 2)
        let profiles = try wg.map { entry in
            try TunnelProfileBuilder.build(text: entry.text,
                                           protocolID: .wireguardVPN,
                                           serverID: UUID(),
                                           serverName: "vps-middle",
                                           deviceID: entry.name,
                                           deviceName: entry.name).profile
        }
        XCTAssertNotEqual(profiles[0].addresses, profiles[1].addresses)
    }

    func testEveryPanelConfigIsCarriedByThisApp() throws {
        for entry in try golden().cases {
            let offers = DeviceConfigurationOffers.offers(protocolID: try serviceID(entry.protocol),
                                                          text: entry.text,
                                                          platform: .iOS)
            XCTAssertTrue(offers.keepsHere, entry.name)
        }
    }

    func testTheHandoffFollowsTheShapeRatherThanTheProtocol() throws {
        for entry in try golden().cases {
            let offers = DeviceConfigurationOffers.offers(protocolID: try serviceID(entry.protocol),
                                                          text: entry.text,
                                                          platform: .iOS)
            if interfaceShaped.contains(entry.protocol) {
                XCTAssertEqual(offers.handoff, .configurationProfile, entry.name)
            } else if entry.protocol == "shadowsocks" {
                guard case .openIn(let url) = offers.handoff else {
                    return XCTFail("the panel's Shadowsocks link was not offered as a link")
                }
                XCTAssertEqual(url.scheme, "ss", entry.name)
            } else {
                XCTAssertNotEqual(offers.handoff, .configurationProfile,
                                  "Reality is not a system VPN type")
            }
            XCTAssertFalse(offers.isEmpty, entry.name)
        }
    }

    func testTheMacIsOfferedNoAmneziaProfile() throws {
        let amnezia = try XCTUnwrap(golden().cases.first { $0.protocol == "amneziawg" })
        let offers = DeviceConfigurationOffers.offers(protocolID: .amneziaWG,
                                                      text: amnezia.text,
                                                      platform: .macOS)
        XCTAssertTrue(offers.keepsHere)
        XCTAssertEqual(offers.handoff, .fileOnly)
        XCTAssertFalse(offers.isEmpty)
    }
}
