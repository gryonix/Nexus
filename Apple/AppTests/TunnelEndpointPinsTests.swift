import ServiceCatalog
import VPNProfile
import VPNTunnel
import XCTest
@testable import gryonixNexus

@MainActor
final class TunnelEndpointPinsTests: XCTestCase {
    private func profile(_ protocolID: ServiceID = .wireguardVPN,
                         endpoint: String = "localhost:51820") -> TunnelProfile {
        TunnelProfile(serverID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                      serverName: "example.org", protocolID: protocolID, deviceID: "phone",
                      deviceName: "Phone", endpoint: endpoint, addresses: ["10.9.0.2/32"])
    }

    private func freshPins() -> TunnelEndpointPins {
        let defaults = UserDefaults(suiteName: "pins-\(UUID().uuidString)")!
        return TunnelEndpointPins(defaults: defaults)
    }

    func testOnlyDomainsOnCarriedDatapathsCanBePinned() {
        XCTAssertTrue(TunnelEndpointPins.canPin(profile()))
        XCTAssertTrue(TunnelEndpointPins.canPin(profile(.xrayReality, endpoint: "vpn.example.org:443")))
        XCTAssertFalse(TunnelEndpointPins.canPin(profile(.openVPN)))
        XCTAssertFalse(TunnelEndpointPins.canPin(profile(endpoint: "203.0.113.5:51820")))
    }

    func testALoopbackAnswerIsRefused() async {
        let pins = freshPins()
        do {
            _ = try await pins.pinAddress(of: profile())
            XCTFail("a loopback address must not be pinned")
        } catch {
            XCTAssertEqual(error as? TunnelEndpointPins.Refusal, .privateAddress("127.0.0.1"))
        }
        XCTAssertNil(pins.pin(for: profile()))
    }

    func testAPinStopsApplyingWhenTheDomainChanges() throws {
        let defaults = UserDefaults(suiteName: "pins-\(UUID().uuidString)")!
        let stored = ["00000000-0000-0000-0000-000000000001/wireguard-vpn/phone":
                        EndpointPin(host: "vpn.example.org", address: "203.0.113.5")]
        defaults.set(try JSONEncoder().encode(stored), forKey: "tunnel.endpointPins")
        let pins = TunnelEndpointPins(defaults: defaults)
        let same = profile(endpoint: "vpn.example.org:51820")
        XCTAssertEqual(pins.pin(for: same)?.address, "203.0.113.5")
        XCTAssertNil(pins.pin(for: profile(endpoint: "other.example.org:51820")))
        pins.unpin(same)
        XCTAssertNil(pins.pin(for: same))
    }
}
