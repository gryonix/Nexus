import ServiceCatalog
import XCTest
@testable import VPNTunnel

final class TunnelProfileBuilderTests: XCTestCase {
    private let wireGuard = """
    [Interface]
    PrivateKey = mInDaw06K0NgfULRObHJjkWD3ahUC8XC1tVjIf6W+Vo=
    Address = 10.9.0.4/32
    DNS = 10.9.0.1
    MTU = 1280

    [Peer]
    PublicKey = JRI8Xc0zKP9kXk8qP84NdUQA04h6DLfFbwJn4g+/PFs=
    PresharedKey = 4Ck2y0nJLsWuDS0kMPy0GgnkKM2mHRE0N9jVdVMlmDU=
    Endpoint = vpn.example.com:51820
    AllowedIPs = 0.0.0.0/0
    PersistentKeepalive = 25
    """

    private let amnezia = """
    [Interface]
    PrivateKey = mInDaw06K0NgfULRObHJjkWD3ahUC8XC1tVjIf6W+Vo=
    Address = 10.10.0.4/32
    DNS = 10.10.0.1
    MTU = 1280
    Jc = 4
    Jmin = 40
    Jmax = 70
    S1 = 78
    S2 = 61
    H1 = 1106457487
    H2 = 1234567890
    H3 = 987654321
    H4 = 1357924680

    [Peer]
    PublicKey = JRI8Xc0zKP9kXk8qP84NdUQA04h6DLfFbwJn4g+/PFs=
    Endpoint = vpn.example.com:51821
    AllowedIPs = 0.0.0.0/0
    PersistentKeepalive = 25
    """

    private let shadowsocks =
        "ss://YWVzLTI1Ni1nY206c2VjcmV0@vpn.example.com:8388#iPhone"

    private let vless = "vless://3f1c0e2a-6a5b-4c7d-8e9f-0a1b2c3d4e5f@vpn.example.com:443"
        + "?encryption=none&security=reality&sni=www.microsoft.com"
        + "&fp=chrome&pbk=xrK4Y_1n7Qk&sid=9a3f&type=tcp&flow=xtls-rprx-vision#iPhone"

    private let openVPN = """
    client
    dev tun
    proto udp
    remote vpn.example.com 1194
    remote backup.example.com 1195
    resolv-retry infinite
    nobind
    persist-key
    persist-tun
    <ca>
    -----BEGIN CERTIFICATE-----
    MIIBhTCCASugAwIBAgIQIRi6zePL6mKjOipn+dNuaTAKBggqhkjOPQQDAjASMRAw
    -----END CERTIFICATE-----
    </ca>
    """

    private func build(_ text: String, protocolID: ServiceID = .wireguardVPN,
                       reusing existing: TunnelProfile? = nil) throws
        -> TunnelProfileBuilder.Built {
        try TunnelProfileBuilder.build(text: text, protocolID: protocolID,
                                       serverID: UUID(), serverName: "Home",
                                       deviceID: "device-1", deviceName: "iPhone",
                                       reusing: existing)
    }

    func testAWireGuardConfigurationBecomesAProfile() throws {
        let built = try build(wireGuard)
        XCTAssertEqual(built.profile.endpoint, "vpn.example.com:51820")
        XCTAssertEqual(built.profile.addresses, ["10.9.0.4/32"])
        XCTAssertEqual(built.profile.dns, ["10.9.0.1"])
        XCTAssertEqual(built.profile.allowedIPs, ["0.0.0.0/0"])
        XCTAssertEqual(built.profile.mtu, 1280)
        XCTAssertFalse(built.profile.isObfuscated)
    }

    func testTheSecretIsTheConfigurationVerbatim() throws {
        let built = try build(wireGuard)
        XCTAssertEqual(built.secret, wireGuard)
        XCTAssertTrue(built.secret.contains("PresharedKey"),
                      "a field the profile has no property for still has to survive")
    }

    func testTheProfileItselfCarriesNoKeyMaterial() throws {
        let built = try build(wireGuard)
        let encoded = try JSONEncoder().encode(built.profile)
        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(json.contains("mInDaw06"), "the private key must never reach the JSON file")
        XCTAssertFalse(json.contains("PresharedKey"))
        XCTAssertFalse(json.contains("JRI8Xc0z"))
    }

    func testAmneziaObfuscationIsDetectedFromTheConfigurationNotTheProtocol() throws {
        XCTAssertTrue(try build(amnezia, protocolID: .amneziaWG).profile.isObfuscated)
        XCTAssertFalse(try build(wireGuard, protocolID: .amneziaWG).profile.isObfuscated,
                       "asking for AmneziaWG does not make a plain config obfuscated")
        XCTAssertTrue(try build(amnezia, protocolID: .wireguardVPN).profile.isObfuscated,
                      "and asking for WireGuard does not make an obfuscated one plain")
    }

    func testRebuildingTheSameTunnelKeepsTheIdentityAWidgetIsPointingAt() throws {
        let first = try build(wireGuard).profile
        let again = try build(wireGuard, reusing: first).profile
        XCTAssertEqual(again.id, first.id)
        XCTAssertEqual(again.createdAt, first.createdAt)
    }

    // MARK: - The other three shapes

    func testAShadowsocksLinkBecomesAProfileNamingItsEndpoint() throws {
        let built = try build(shadowsocks, protocolID: .shadowsocks)

        XCTAssertEqual(built.profile.endpoint, "vpn.example.com:8388")
        XCTAssertEqual(built.secret, "ss://YWVzLTI1Ni1nY206c2VjcmV0@vpn.example.com:8388#iPhone",
                       "the link goes to the datapath verbatim")
        XCTAssertEqual(built.profile.addresses, [],
                       "a proxy has no interface, and inventing one would print it as a fact")
        XCTAssertEqual(built.profile.allowedIPs, ["0.0.0.0/0", "::/0"],
                       "a TUN inbound takes everything; nothing else reads as a split tunnel")
        XCTAssertFalse(built.profile.isObfuscated)
    }

    func testTheLegacyShadowsocksFormIsReadRatherThanRefused() throws {
        let legacy = "ss://" + Data("aes-256-gcm:secret@vpn.example.com:8388".utf8)
            .base64EncodedString() + "#iPhone"

        let built = try build(legacy, protocolID: .shadowsocks)

        XCTAssertEqual(built.profile.endpoint, "vpn.example.com:8388")
    }

    func testAVLESSLinkBecomesAProfileNamingItsEndpoint() throws {
        let built = try build(vless, protocolID: .xrayReality)

        XCTAssertEqual(built.profile.endpoint, "vpn.example.com:443")
        XCTAssertEqual(built.secret, vless)
        XCTAssertFalse(built.profile.isObfuscated,
                       "the flag means AmneziaWG's nine values, not \"hard to recognise\"")
    }

    func testAnOpenVPNProfileIsNamedByItsFirstRemote() throws {
        let built = try build(openVPN, protocolID: .openVPN)

        XCTAssertEqual(built.profile.endpoint, "vpn.example.com:1194")
        XCTAssertEqual(built.secret, openVPN.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Refusals

    func testAProtocolWithNoDatapathIsRefusedByName() {
        let unknown = ServiceID(rawValue: "some-future-protocol")
        XCTAssertThrowsError(try build(wireGuard, protocolID: unknown)) { error in
            XCTAssertEqual(error as? TunnelProfileBuilder.Failure, .protocolNotCarried(unknown))
        }
    }

    func testAConfigurationOfTheWrongShapeIsUnreadableRatherThanAccepted() {
        XCTAssertThrowsError(try build(wireGuard, protocolID: .shadowsocks)) { error in
            XCTAssertEqual(error as? TunnelProfileBuilder.Failure,
                           .unreadableLink(.noLink(.shadowsocks)))
        }
        XCTAssertThrowsError(try build(shadowsocks, protocolID: .openVPN)) { error in
            XCTAssertEqual(error as? TunnelProfileBuilder.Failure,
                           .unreadableProfile(.noRemote))
        }
    }

    func testALinkWithoutAPortIsRefused() {
        XCTAssertThrowsError(try build("vless://uuid@vpn.example.com#iPhone",
                                       protocolID: .xrayReality)) { error in
            XCTAssertEqual(error as? TunnelProfileBuilder.Failure,
                           .unreadableLink(.noEndpoint(.vless)))
        }
    }

    func testATruncatedConfigurationIsUnreadableRatherThanUnsupported() {
        XCTAssertThrowsError(try build("[Interface]\nPrivateKey = x")) { error in
            XCTAssertEqual(error as? TunnelProfileBuilder.Failure, .unreadable(.missingPeer),
                           "the reason must name what is missing")
        }
    }

    func testASharedLinkIsNotMistakenForAWireGuardTunnel() {
        XCTAssertThrowsError(try build("ss://YWVzOnBhc3N3b3Jk@example.com:8388"))
    }
}
