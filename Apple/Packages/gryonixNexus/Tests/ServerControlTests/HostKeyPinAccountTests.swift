import XCTest
@testable import ServerControl

final class HostKeyPinAccountTests: XCTestCase {
    private let deployment = UUID(uuidString: "1B4E28BA-2FA1-11D2-883F-0016D3CCA427")!

    func testTheCurrentAccountIsStableForADeploymentAndSlot() {
        XCTAssertEqual(HostKeyPinAccounts.current(deployment: deployment, slot: .vps),
                       HostKeyPinAccounts.current(deployment: deployment, slot: .vps))
        XCTAssertEqual(HostKeyPinAccounts.current(deployment: deployment, slot: .home),
                       HostKeyPinAccounts.current(deployment: deployment, slot: .home))
    }

    func testTheCurrentAccountNamesTheNode() {
        for slot in [DeploymentNode.LegacySlot.vps, .home] {
            let node = Deployment.nodeID(for: deployment, slot: slot)
            XCTAssertEqual(HostKeyPinAccounts.current(deployment: deployment, slot: slot),
                           "hostkey-\(deployment.uuidString)-\(node.uuidString)")
        }
    }

    func testTheTwoNodesOfAPairDoNotShareAnAccount() {
        XCTAssertNotEqual(HostKeyPinAccounts.current(deployment: deployment, slot: .vps),
                          HostKeyPinAccounts.current(deployment: deployment, slot: .home))
    }

    func testTheLegacyAccountIsExactlyWhatWasWrittenBefore() {
        XCTAssertEqual(HostKeyPinAccounts.legacy(deployment: deployment, slot: .vps),
                       "hostkey-\(deployment.uuidString)-vps")
        XCTAssertEqual(HostKeyPinAccounts.legacy(deployment: deployment, slot: .home),
                       "hostkey-\(deployment.uuidString)-home")
    }

    func testTheOldAndNewAccountsAreDifferentNames() {
        for slot in [DeploymentNode.LegacySlot.vps, .home] {
            XCTAssertNotEqual(HostKeyPinAccounts.current(deployment: deployment, slot: slot),
                              HostKeyPinAccounts.legacy(deployment: deployment, slot: slot))
        }
    }

    func testDifferentDeploymentsNeverShareAnAccount() {
        let other = UUID()
        XCTAssertNotEqual(HostKeyPinAccounts.current(deployment: deployment, slot: .vps),
                          HostKeyPinAccounts.current(deployment: other, slot: .vps))
    }
}
