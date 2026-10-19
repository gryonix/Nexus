import XCTest
@testable import VPNProfile

final class EndpointPinTests: XCTestCase {
    private let pin = EndpointPin(host: "vpn.example.org", address: "203.0.113.5")

    func testReplacesOnlyTheHost() {
        XCTAssertEqual(pin.replacingHost(of: "vpn.example.org:51820"), "203.0.113.5:51820")
        XCTAssertEqual(pin.replacingHost(of: "VPN.example.org:443"), "203.0.113.5:443")
    }

    func testAnotherHostIsLeftAlone() {
        XCTAssertNil(pin.replacingHost(of: "other.example.org:51820"))
        XCTAssertNil(pin.replacingHost(of: "vpn.example.org"))
    }

    func testIPv6IsBracketed() {
        let six = EndpointPin(host: "vpn.example.org", address: "2001:db8::1")
        XCTAssertEqual(six.replacingHost(of: "vpn.example.org:51820"), "[2001:db8::1]:51820")
        XCTAssertEqual(EndpointPin.split("[2001:db8::1]:443")?.host, "2001:db8::1")
    }

    func testPrivateAddressesAreNotPublic() {
        for address in ["10.53.0.53", "192.168.1.1", "172.20.0.1", "100.64.0.1", "127.0.0.1",
                        "169.254.1.1", "0.0.0.0", "224.0.0.1", "::1", "fd00::1", "fe80::1"] {
            XCTAssertFalse(EndpointPin.isPublic(address), address)
        }
        XCTAssertTrue(EndpointPin.isPublic("203.0.113.5"))
        XCTAssertTrue(EndpointPin.isPublic("2001:db8::1"))
        XCTAssertFalse(EndpointPin.isPublic("vpn.example.org"))
    }

    func testProviderConfigurationRoundTrip() {
        XCTAssertEqual(EndpointPin(providerConfiguration: pin.providerEntries), pin)
        let inner = [VPNTunnelKeys.endpointPinHost: "vpn.example.org", VPNTunnelKeys.endpointPinAddress: "10.0.0.1"]
        XCTAssertNil(EndpointPin(providerConfiguration: inner))
        XCTAssertNil(EndpointPin(providerConfiguration: [:]))
    }
}
