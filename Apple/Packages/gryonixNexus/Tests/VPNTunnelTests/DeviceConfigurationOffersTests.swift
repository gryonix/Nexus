import ServiceCatalog
import XCTest
@testable import VPNProfile
@testable import VPNTunnel

final class DeviceConfigurationOffersTests: XCTestCase {
    private let wireGuard = """
    [Interface]
    PrivateKey = qYZtvqq1Y+yrS6oRJVgah3DZlRxvqSuQJQvMGYFI+jI=
    Address = 10.9.0.2/32

    [Peer]
    PublicKey = R1XTXmuiEo976mXG7BVbjc5DnzkGsKqJsrIV8WEnih4=
    Endpoint = vpn.example.com:51820
    AllowedIPs = 0.0.0.0/0
    """

    func testWireGuardIsBothKeptHereAndInstallable() {
        let offers = DeviceConfigurationOffers.offers(protocolID: .wireguardVPN,
                                                      text: wireGuard,
                                                      platform: .iOS)
        XCTAssertTrue(offers.keepsHere)
        XCTAssertEqual(offers.handoff, .configurationProfile)
        XCTAssertFalse(offers.isEmpty)
    }

    func testOpenVPNIsHandedOnRatherThanKeptHere() {
        let ovpn = """
        client
        dev tun
        proto udp
        remote vpn.example.com 1194
        """
        let offers = DeviceConfigurationOffers.offers(protocolID: .openVPN,
                                                      text: ovpn,
                                                      platform: .iOS)
        XCTAssertFalse(offers.keepsHere,
                       "no OpenVPN runtime is linked — offering the tunnel would fail after the tap")
        XCTAssertEqual(offers.handoff, .configurationProfile)
        XCTAssertFalse(offers.isEmpty)
    }

    func testAnUnparsableOpenVPNProfileIsFileOnly() {
        let offers = DeviceConfigurationOffers.offers(protocolID: .openVPN,
                                                      text: "this is not an OpenVPN profile",
                                                      platform: .iOS)
        XCTAssertFalse(offers.keepsHere,
                       "text the builder would refuse must not be offered as a tunnel")
        XCTAssertEqual(offers.handoff, .fileOnly)
        XCTAssertTrue(offers.isEmpty)
    }

    func testAnOpenVPNProfileWithNoRemoteIsNotOfferedAsATunnel() {
        let offers = DeviceConfigurationOffers.offers(protocolID: .openVPN,
                                                      text: "client\ndev tun\nproto udp\n",
                                                      platform: .iOS)
        XCTAssertFalse(offers.keepsHere,
                       "a profile naming no server cannot become a tunnel on this device")
    }

    func testShadowsocksIsBothKeptHereAndOpenedInItsOwnApp() {
        let text = "ss://YWVzLTI1Ni1nY206c2VjcmV0@vpn.example.com:8388#phone\n"
        let offers = DeviceConfigurationOffers.offers(protocolID: .shadowsocks,
                                                      text: text,
                                                      platform: .iOS)
        XCTAssertTrue(offers.keepsHere)
        guard case .openIn(let url) = offers.handoff else {
            return XCTFail("a link the panel emitted was not offered as a link")
        }
        XCTAssertEqual(url.scheme, "ss")
    }

    func testXrayRealityIsCarriedHereWithNoSystemProfile() {
        let link = "vless://3f1c0e2a-6a5b-4c7d-8e9f-0a1b2c3d4e5f@vpn.example.com:443"
            + "?encryption=none&security=reality&sni=www.microsoft.com"
            + "&fp=chrome&pbk=xrK4Y_1n7Qk&sid=9a3f&type=tcp&flow=xtls-rprx-vision#phone"
        let offers = DeviceConfigurationOffers.offers(protocolID: .xrayReality,
                                                      text: link,
                                                      platform: .iOS)
        XCTAssertTrue(offers.keepsHere)
        XCTAssertNotEqual(offers.handoff, .configurationProfile,
                          "Reality is not a system VPN type")
        XCTAssertFalse(offers.isEmpty, "the sheet must not read as \"nothing to do\"")
    }

    func testAShadowsocksEntryWithoutALinkIsFileOnly() {
        let offers = DeviceConfigurationOffers.offers(protocolID: .shadowsocks,
                                                      text: "no link here",
                                                      platform: .iOS)
        XCTAssertFalse(offers.keepsHere)
        XCTAssertEqual(offers.handoff, .fileOnly)
        XCTAssertTrue(offers.isEmpty)
    }

    func testAWireGuardConfigurationWithNoPeerIsNotOfferedAsATunnel() {
        let truncated = """
        [Interface]
        PrivateKey = qYZtvqq1Y+yrS6oRJVgah3DZlRxvqSuQJQvMGYFI+jI=
        Address = 10.9.0.2/32
        """
        let offers = DeviceConfigurationOffers.offers(protocolID: .wireguardVPN,
                                                      text: truncated,
                                                      platform: .iOS)
        XCTAssertFalse(offers.keepsHere)
    }

    /// A protocol id this build has no datapath for
    func testAProtocolWithNoDatapathIsNotCarried() {
        let offers = DeviceConfigurationOffers.offers(protocolID: ServiceID(rawValue: "some-future-protocol"),
                                                      text: wireGuard,
                                                      platform: .iOS)
        XCTAssertFalse(offers.keepsHere)
    }

    // MARK: - The name the profile is written under

    func testTheExtensionIsReplacedRatherThanAppended() {
        XCTAssertEqual(DeviceConfigurationOffers.profileFileName(from: "phone.conf",
                                                                  deviceName: "phone"),
                       "phone.mobileconfig")
        XCTAssertEqual(DeviceConfigurationOffers.profileFileName(from: "laptop.ovpn",
                                                                  deviceName: "laptop"),
                       "laptop.mobileconfig")
    }

    /// Only the LAST dot is an extension
    func testOnlyTheFinalDotIsTreatedAsAnExtension() {
        XCTAssertEqual(DeviceConfigurationOffers.profileFileName(from: "iPhone 17.pro.conf",
                                                                  deviceName: "iPhone 17.pro"),
                       "iPhone 17.pro.mobileconfig")
    }

    func testANameWithNoStemFallsBackToTheDevice() {
        XCTAssertEqual(DeviceConfigurationOffers.profileFileName(from: ".conf",
                                                                  deviceName: "phone"),
                       "phone.mobileconfig")
        XCTAssertEqual(DeviceConfigurationOffers.profileFileName(from: "",
                                                                  deviceName: "phone"),
                       "phone.mobileconfig")
    }

    func testANameWithNoExtensionIsKeptWhole() {
        XCTAssertEqual(DeviceConfigurationOffers.profileFileName(from: "phone",
                                                                  deviceName: "other"),
                       "phone.mobileconfig")
    }
}
