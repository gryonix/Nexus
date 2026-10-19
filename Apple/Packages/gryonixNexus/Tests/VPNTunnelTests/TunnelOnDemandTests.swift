import XCTest
@testable import VPNTunnel

final class TunnelOnDemandTests: XCTestCase {
    func testAPolicyThatIsOffProducesNoRulesAtAll() {
        var policy = TunnelOnDemandPolicy.off
        policy.trustedNetworks = ["Home"]

        XCTAssertEqual(policy.rules, [])
    }

    func testExceptedNetworksComeBeforeAnythingConnects() {
        let policy = TunnelOnDemandPolicy(isEnabled: true, scope: .anyNetwork,
                                          trustedNetworks: ["Home", "Office"])

        XCTAssertEqual(policy.rules, [
            .disconnectOnWiFi(networks: ["Home", "Office"]),
            .connectOnWiFi(networks: []),
            .connectOnCellular,
            .connectOnAnything,
        ])
    }

    func testOnlyListedConnectsThereAndStaysDownOnOtherWiFi() {
        let policy = TunnelOnDemandPolicy(isEnabled: true, scope: .wiFiOnly, networkMode: .onlyListed,
                                          trustedNetworks: ["Cafe"])

        XCTAssertEqual(policy.rules, [
            .connectOnWiFi(networks: ["Cafe"]),
            .disconnectOnWiFi(networks: []),
            .disconnectOnCellular,
        ])
    }

    func testWiFiOnlyKeepsCellularDown() {
        let policy = TunnelOnDemandPolicy(isEnabled: true, scope: .wiFiOnly, trustedNetworks: [])

        XCTAssertEqual(policy.rules, [.connectOnWiFi(networks: []), .disconnectOnCellular])
    }

    func testCellularOnlyIgnoresTheNetworkList() {
        let policy = TunnelOnDemandPolicy(isEnabled: true, scope: .cellularOnly, networkMode: .onlyListed,
                                          trustedNetworks: ["Home"])

        XCTAssertEqual(policy.rules, [.disconnectOnWiFi(networks: []), .connectOnCellular])
    }

    func testAnEmptyNetworkNameIsDropped() {
        let policy = TunnelOnDemandPolicy(isEnabled: true, scope: .wiFiOnly,
                                          trustedNetworks: ["", "  Home  "])

        XCTAssertEqual(policy.rules.first, .disconnectOnWiFi(networks: ["  Home  "]))
    }

    func testNoListedNetworksMeansNoNetworkRule() {
        let policy = TunnelOnDemandPolicy(isEnabled: true, scope: .anyNetwork, networkMode: .onlyListed,
                                          trustedNetworks: [])

        XCTAssertEqual(policy.rules, [.connectOnWiFi(networks: []), .connectOnCellular, .connectOnAnything])
    }
}
