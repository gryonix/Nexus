import ServerControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

@MainActor
final class WakeOnLANButtonTests: XCTestCase {
    private func deployment(_ scope: DeploymentScope, host: String = "192.168.1.40") -> Deployment {
        Deployment(name: "home",
                   topology: .singleHost,
                   domain: "lan.local",
                   entry: HostEndpoint(host: host, port: 22, user: "gryonix"),
                   scope: scope)
    }

    func testTheButtonIsOfferedForAMachineOnTheOwnersOwnNetwork() {
        XCTAssertTrue(WakeOnLANAvailability.isOffered(for: deployment(.localOnly)))
    }

    func testAMachineAtAHomeAddressIsOfferedItWhateverItsScope() {
        for scope in DeploymentScope.allCases {
            XCTAssertTrue(WakeOnLANAvailability.isOffered(for: deployment(scope)), "\(scope)")
        }
        XCTAssertTrue(WakeOnLANAvailability.isOffered(for: deployment(.publicInternet, host: "draco.local")))
    }

    func testARentedServerOnAPublicAddressIsNotOfferedIt() {
        XCTAssertFalse(WakeOnLANAvailability.isOffered(for: deployment(.publicInternet, host: "203.0.113.10")))
        XCTAssertTrue(WakeOnLANAvailability.isOffered(for: deployment(.dynamicDNS, host: "203.0.113.10")))
    }

    func testTheStoredAddressSurvivesTheDisk() throws {
        var subject = deployment(.localOnly)
        subject.wakeOnLANMAC = "aa:bb:cc:dd:ee:ff"
        let data = try JSONEncoder().encode(subject)
        let decoded = try JSONDecoder().decode(Deployment.self, from: data)
        XCTAssertEqual(decoded.wakeOnLANMAC, "aa:bb:cc:dd:ee:ff")
    }

    func testADeploymentWrittenBeforeTheFieldExistedStillLoads() throws {
        var subject = deployment(.localOnly)
        subject.wakeOnLANMAC = nil
        let data = try JSONEncoder().encode(subject)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "wakeOnLANMAC")
        let stripped = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(Deployment.self, from: stripped)
        XCTAssertNil(decoded.wakeOnLANMAC)
    }
}
