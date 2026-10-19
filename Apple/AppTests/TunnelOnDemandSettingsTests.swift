import ServiceCatalog
import VPNTunnel
import XCTest
@testable import gryonixNexus

/// The tunnel restarts on its own by default
@MainActor
final class TunnelOnDemandSettingsTests: XCTestCase {
    func testAFreshInstallKeepsTheTunnelUpAndAChoiceIsKept() throws {
        let name = "TunnelOnDemandSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertTrue(TunnelOnDemandSettings(defaults: defaults).isEnabled)
        TunnelOnDemandSettings(defaults: defaults).isEnabled = false
        XCTAssertFalse(TunnelOnDemandSettings(defaults: defaults).isEnabled)
    }

    func testASwitchCarriesTheDNSAndTheWayTheServerIsReached() {
        let profile = TunnelProfile(serverID: UUID(), serverName: "example.net", protocolID: .shadowsocks,
                                    deviceID: "d1", deviceName: "iPhone", endpoint: "vpn.example.net:8388",
                                    addresses: [], dns: ["1.1.1.1", "1.0.0.1"])
        let carry = TunnelCarry(of: profile, pinned: true)
        XCTAssertEqual(carry.dns, ["1.1.1.1", "1.0.0.1"])
        XCTAssertTrue(carry.pinned)
    }
}
