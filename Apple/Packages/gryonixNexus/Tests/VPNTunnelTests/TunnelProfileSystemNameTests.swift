import XCTest
import ServiceCatalog
@testable import VPNTunnel

final class TunnelProfileSystemNameTests: XCTestCase {
    private func profile(server: String, endpoint: String) -> TunnelProfile {
        TunnelProfile(serverID: UUID(), serverName: server, protocolID: .wireguardVPN,
                      deviceID: "d", deviceName: "iPhone", endpoint: endpoint, addresses: [])
    }

    func testServerNameThenProtocol() {
        XCTAssertEqual(profile(server: "example.org", endpoint: "vpn.example.org:51821").systemName,
                       "example.org · WireGuard")
    }

    func testHostWithoutPortWhenUnnamed() {
        XCTAssertEqual(profile(server: "", endpoint: "203.0.113.7:51821").systemName, "203.0.113.7 · WireGuard")
        XCTAssertEqual(profile(server: "", endpoint: "[2001:db8::1]:51821").systemName, "2001:db8::1 · WireGuard")
    }
}
