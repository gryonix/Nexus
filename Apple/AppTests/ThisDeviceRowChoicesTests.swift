import AgentControl
import ServiceCatalog
import VPNTunnel
import XCTest

@testable import gryonixNexus

/// What the This device rows offer and land on
final class ThisDeviceRowChoicesTests: XCTestCase {
    private let serverID = UUID()

    private func profile(_ protocolID: ServiceID, device: String, named name: String,
                         dns: [String] = [], server: UUID? = nil) -> TunnelProfile {
        TunnelProfile(serverID: server ?? serverID, serverName: "orion", protocolID: protocolID,
                      deviceID: device, deviceName: name, endpoint: "vpn.example.net:51820",
                      addresses: ["10.9.0.4/32"], dns: dns)
    }

    func testASwitchedServerKeepsTheProtocolItHas() {
        let landed = ThisDeviceTunnelChoices.landingProtocol(among: [.wireguardVPN, .amneziaWG],
                                                             keeping: .amneziaWG)
        XCTAssertEqual(landed, .amneziaWG)
    }

    func testASwitchedServerWithoutTheProtocolTakesItsFirst() {
        let landed = ThisDeviceTunnelChoices.landingProtocol(among: [.shadowsocks, .xrayReality],
                                                             keeping: .wireguardVPN)
        XCTAssertEqual(landed, .shadowsocks)
        XCTAssertNil(ThisDeviceTunnelChoices.landingProtocol(among: [], keeping: .wireguardVPN))
    }

    func testTheKeptTunnelPrefersThisDevicesOwn() {
        let borrowed = profile(.wireguardVPN, device: "b", named: "Morgan's laptop")
        let own = profile(.wireguardVPN, device: "a", named: "iPhone")
        let elsewhere = profile(.wireguardVPN, device: "c", named: "iPhone", server: UUID())
        let kept = ThisDeviceTunnelChoices.keptProfile(in: [borrowed, own, elsewhere], serverID: serverID,
                                                       protocolID: .wireguardVPN, ownName: "iPhone")
        XCTAssertEqual(kept?.id, own.id)
    }

    func testABorrowedTunnelIsKeptWhenThereIsNoOwn() {
        let borrowed = profile(.wireguardVPN, device: "b", named: "Morgan's laptop")
        let kept = ThisDeviceTunnelChoices.keptProfile(in: [borrowed], serverID: serverID,
                                                       protocolID: .wireguardVPN, ownName: "iPhone")
        XCTAssertEqual(kept?.id, borrowed.id)
        XCTAssertNil(ThisDeviceTunnelChoices.keptProfile(in: [borrowed], serverID: serverID,
                                                         protocolID: .amneziaWG, ownName: "iPhone"))
    }

    func testOtherDevicesLeaveOutThisDevicesOwn() {
        let devices = [VPNClientDevice(id: "a", name: "iPhone", detail: ""),
                       VPNClientDevice(id: "b", name: "Morgan's laptop", detail: "")]
        let others = ThisDeviceTunnelChoices.otherDevices(devices, ownDeviceID: "a")
        XCTAssertEqual(others.map(\.id), ["b"])
        XCTAssertEqual(ThisDeviceTunnelChoices.otherDevices(devices, ownDeviceID: nil).count, 2)
    }

    func testAmneziaWGIsNotMarkedButObfuscatedWireGuardIs() {
        XCTAssertEqual(ThisDeviceTunnelChoices.protocolLabel(.amneziaWG, obfuscated: true),
                       ServiceID.amneziaWG.displayName)
        XCTAssertEqual(ThisDeviceTunnelChoices.protocolLabel(.wireguardVPN, obfuscated: true),
                       "\(ServiceID.wireguardVPN.displayName) (obfuscated)")
        XCTAssertEqual(ThisDeviceTunnelChoices.protocolLabel(.wireguardVPN, obfuscated: false),
                       ServiceID.wireguardVPN.displayName)
    }

    func testTheServersListedDNSWinsOverTheProfiles() {
        let current = profile(.shadowsocks, device: "a", named: "iPhone")
        let listed = [VPNClientDevice(id: "a", name: "iPhone", detail: "", dns: [LocalDNS.serverAddress])]
        XCTAssertEqual(ThisDeviceTunnelChoices.dns(of: current, listed: listed), [LocalDNS.serverAddress])
    }

    func testAnUnlistedOrSilentDeviceKeepsTheProfilesDNS() {
        let current = profile(.wireguardVPN, device: "a", named: "iPhone", dns: ["9.9.9.9"])
        let silent = [VPNClientDevice(id: "a", name: "iPhone", detail: "")]
        XCTAssertEqual(ThisDeviceTunnelChoices.dns(of: current, listed: silent), ["9.9.9.9"])
        XCTAssertEqual(ThisDeviceTunnelChoices.dns(of: current, listed: []), ["9.9.9.9"])
    }

    func testTheRelayAskedAfterTheChoiceIsNotShownAsTheChoice() {
        let current = profile(.wireguardVPN, device: "a", named: "iPhone",
                              dns: ["9.9.9.9", LocalDNS.serverAddress])
        XCTAssertEqual(ThisDeviceTunnelChoices.dns(of: current, listed: []), ["9.9.9.9"])
        XCTAssertEqual(LocalDNS.chosen([LocalDNS.serverAddress]), [LocalDNS.serverAddress])
    }
}
