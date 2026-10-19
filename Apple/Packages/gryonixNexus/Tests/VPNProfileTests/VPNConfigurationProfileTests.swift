import XCTest
@testable import VPNProfile
import ServiceCatalog

final class VPNConfigurationProfileTests: XCTestCase {
    private let text = """
    [Interface]
    PrivateKey = mInDaw06K0NgfULRObHJjkWD3ahUC8XC1tVjIf6W+Vo=
    Address = 10.9.0.4/32

    [Peer]
    PublicKey = JRI8Xc0zKP9kXk8qP84NdUQA04h6DLfFbwJn4g+/PFs=
    Endpoint = vpn.example.com:51820
    AllowedIPs = 0.0.0.0/0
    """

    private func profile(_ protocolID: ServiceID = .wireguardVPN,
                         platform: VPNConfigurationProfile.Platform = .iOS,
                         identifier: String = "server-1.wireguard-vpn.phone")
        throws -> [String: Any] {
        let config = try WireGuardQuickConfig(parsing: text)
        let data = try VPNConfigurationProfile.plist(for: config,
                                                     protocolID: protocolID,
                                                     deviceName: "Phone",
                                                     identifier: identifier,
                                                     platform: platform)
        return try XCTUnwrap(PropertyListSerialization.propertyList(
            from: data, format: nil) as? [String: Any])
    }

    private func payload(_ root: [String: Any]) throws -> [String: Any] {
        let content = try XCTUnwrap(root["PayloadContent"] as? [[String: Any]])
        return try XCTUnwrap(content.first)
    }

    // MARK: - Which app runs the tunnel

    func testTheHandlerIsTheRealAppForEachPlatform() {
        XCTAssertEqual(VPNConfigurationProfile.handlerBundleID(for: .wireguardVPN, on: .iOS),
                       "com.wireguard.ios")
        XCTAssertEqual(VPNConfigurationProfile.handlerBundleID(for: .wireguardVPN, on: .macOS),
                       "com.wireguard.macos")
        XCTAssertEqual(VPNConfigurationProfile.handlerBundleID(for: .amneziaWG, on: .iOS),
                       "org.amnezia.awg")
    }

    func testAmneziaWGIsNotOfferedOnMac() {
        XCTAssertNil(VPNConfigurationProfile.handlerBundleID(for: .amneziaWG, on: .macOS))
        XCTAssertFalse(VPNConfigurationProfile.isSupported(.amneziaWG, on: .macOS))
    }

    func testProxyProtocolsAreNotOffered() {
        for id in [ServiceID.shadowsocks, .xrayReality] {
            XCTAssertFalse(VPNConfigurationProfile.isSupported(id, on: .iOS), id.rawValue)
            XCTAssertFalse(VPNConfigurationProfile.isSupported(id, on: .macOS), id.rawValue)
        }
    }

    func testOpenVPNIsOfferedOnIOSOnly() {
        XCTAssertEqual(VPNConfigurationProfile.handlerBundleID(for: .openVPN, on: .iOS),
                       "net.openvpn.connect.app")
        XCTAssertNil(VPNConfigurationProfile.handlerBundleID(for: .openVPN, on: .macOS))
    }

    func testBuildingRefusesAnUnsupportedProtocol() throws {
        let config = try WireGuardQuickConfig(parsing: text)
        XCTAssertThrowsError(try VPNConfigurationProfile.plist(for: config,
                                                               protocolID: .shadowsocks,
                                                               deviceName: "Phone",
                                                               identifier: "x",
                                                               platform: .iOS))
    }

    // MARK: - What the profile says

    func testPayloadIsAVPNPayloadForTheNamedApp() throws {
        let payload = try payload(try profile())
        XCTAssertEqual(payload["PayloadType"] as? String, "com.apple.vpn.managed")
        XCTAssertEqual(payload["VPNType"] as? String, "VPN")
        XCTAssertEqual(payload["VPNSubType"] as? String, "com.wireguard.ios")
        XCTAssertEqual(payload["UserDefinedName"] as? String, "Phone")
    }

    func testTheConfigurationTravelsVerbatim() throws {
        let vendor = try XCTUnwrap(try payload(try profile())["VendorConfig"] as? [String: Any])
        XCTAssertEqual(vendor["WgQuickConfig"] as? String, text)
    }

    func testTheServerAddressIsNamed() throws {
        let vpn = try XCTUnwrap(try payload(try profile())["VPN"] as? [String: Any])
        XCTAssertEqual(vpn["RemoteAddress"] as? String, "vpn.example.com:51820")
    }

    // MARK: - Installing twice

    /// The OS keys installed profiles by `PayloadIdentifier`
    func testTheSameDeviceProducesTheSameIdentityEveryTime() throws {
        let first = try profile()
        let second = try profile()
        XCTAssertEqual(first["PayloadIdentifier"] as? String, second["PayloadIdentifier"] as? String)
        XCTAssertEqual(first["PayloadUUID"] as? String, second["PayloadUUID"] as? String)
        XCTAssertEqual(try payload(first)["PayloadUUID"] as? String,
                       try payload(second)["PayloadUUID"] as? String)
    }

    /// ...and a different device must not collide with it
    func testADifferentDeviceGetsADifferentIdentity() throws {
        let phone = try profile(identifier: "server-1.wireguard-vpn.phone")
        let laptop = try profile(identifier: "server-1.wireguard-vpn.laptop")
        XCTAssertNotEqual(phone["PayloadIdentifier"] as? String, laptop["PayloadIdentifier"] as? String)
        XCTAssertNotEqual(phone["PayloadUUID"] as? String, laptop["PayloadUUID"] as? String)
    }

    func testTheDerivedUUIDIsWellFormed() {
        let value = VPNConfigurationProfile.uuid(from: "anything")
        XCTAssertNotNil(UUID(uuidString: value), value)
        XCTAssertEqual(value.count, 36)
        // Version 5 (name-based) and the RFC 4122 variant.
        XCTAssertEqual(Array(value)[14], "5", value)
        XCTAssertTrue("89AB".contains(Array(value)[19]), value)
    }

    // MARK: - Shape

    func testItIsAnXMLPropertyListAppleWillAccept() throws {
        let config = try WireGuardQuickConfig(parsing: text)
        let data = try VPNConfigurationProfile.plist(for: config,
                                                     protocolID: .wireguardVPN,
                                                     deviceName: "Phone",
                                                     identifier: "id",
                                                     platform: .iOS)
        let head = String(decoding: data.prefix(64), as: UTF8.self)
        XCTAssertTrue(head.hasPrefix("<?xml"), head)
        let root = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil)
                                 as? [String: Any])
        XCTAssertEqual(root["PayloadType"] as? String, "Configuration")
        XCTAssertEqual(root["PayloadVersion"] as? Int, 1)
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(root["PayloadUUID"] as? String)))
    }

    // MARK: - The OpenVPN payload

    private func openVPNPayload(platform: VPNConfigurationProfile.Platform = .iOS)
        throws -> [String: Any] {
        let config = try OpenVPNProfileConfig(parsing: """
        client
        dev tun
        remote vpn.example.com 1194
        <ca>
        -----BEGIN CERTIFICATE-----
        MIIB1jCCAX2gAwIBAgIUAAAA
        -----END CERTIFICATE-----
        </ca>
        """)
        let data = try VPNConfigurationProfile.plist(for: config,
                                                     deviceName: "Phone",
                                                     identifier: "server-1.openvpn.phone",
                                                     platform: platform)
        let root = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil)
                                 as? [String: Any])
        return try payload(root)
    }

    func testTheOpenVPNPayloadNamesOpenVPNConnect() throws {
        let payload = try openVPNPayload()
        XCTAssertEqual(payload["PayloadType"] as? String, "com.apple.vpn.managed")
        XCTAssertEqual(payload["VPNType"] as? String, "VPN")
        XCTAssertEqual(payload["VPNSubType"] as? String, "net.openvpn.connect.app")
    }

    func testTheOpenVPNServerAddressIsTheLiteralDEFAULT() throws {
        let vpn = try XCTUnwrap(try openVPNPayload()["VPN"] as? [String: Any])
        XCTAssertEqual(vpn["RemoteAddress"] as? String, "DEFAULT")
    }

    /// The whole difference from WireGuard: the profile arrives taken apart
    func testTheOpenVPNVendorConfigIsTheDirectivesRatherThanTheFile() throws {
        let vendor = try XCTUnwrap(try openVPNPayload()["VendorConfig"] as? [String: Any])
        XCTAssertEqual(vendor["client"] as? String, "NOARGS")
        XCTAssertEqual(vendor["remote"] as? String, "vpn.example.com 1194")
        XCTAssertEqual(vendor["vpn-on-demand"] as? String, "0")
        XCTAssertNil(vendor["WgQuickConfig"])
    }

    func testAMacIsNotHandedAnOpenVPNProfile() throws {
        XCTAssertThrowsError(try openVPNPayload(platform: .macOS))
    }
}
