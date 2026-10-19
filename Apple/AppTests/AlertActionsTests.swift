import ServerControl
import UserNotifications
import XCTest

@testable import gryonixNexus

/// Buttons on server alerts find their server and machine
final class AlertActionsTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "AlertActionsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testBlockReadsTheAddressAndTheMachineName() {
        let gnx: [String: Any] = ["server_id": "srv", "kind": "gnx.alert.ssh_login",
                                  "args": ["gvps", "root", "1.2.3.4 by key"], "address": "1.2.3.4"]
        let action = AlertAction(action: AlertAction.Verb.block.rawValue, gnx: gnx)
        XCTAssertEqual(action?.target, "1.2.3.4")
        XCTAssertEqual(action?.host, "gvps")
        XCTAssertEqual(action?.server, "srv")
    }

    func testRestartReadsTheContainerFromTheArguments() {
        let gnx: [String: Any] = ["server_id": "srv", "args": ["orion", "vaultwarden", "unhealthy"]]
        XCTAssertEqual(AlertAction(action: AlertAction.Verb.restart.rawValue, gnx: gnx)?.target, "vaultwarden")
    }

    func testATapWithoutAButtonOrATargetIsNoAction() {
        let gnx: [String: Any] = ["server_id": "srv", "args": ["gvps"]]
        XCTAssertNil(AlertAction(action: UNNotificationDefaultActionIdentifier, gnx: gnx))
        XCTAssertNil(AlertAction(action: AlertAction.Verb.block.rawValue, gnx: gnx))
        XCTAssertNil(AlertAction(action: AlertAction.Verb.restart.rawValue, gnx: gnx))
    }

    func testEveryButtonKindHasACategory() {
        let categories = AlertActions.categories()
        XCTAssertEqual(Set(categories.map(\.identifier)), ["gnx.alert.ssh_login", "gnx.alert.service"])
    }

    func testARelayIDRemembersTheMachine() {
        let defaults = defaults()
        let deployment = UUID()
        let node = UUID()
        RelayServers.remember("a", as: deployment, host: .home, in: defaults)
        RelayServers.remember("b", as: deployment, host: .node(node), in: defaults)
        XCTAssertEqual(RelayServers.target(of: "a", in: defaults)?.host, .home)
        XCTAssertEqual(RelayServers.target(of: "b", in: defaults)?.host, .node(node))
        XCTAssertEqual(RelayServers.deploymentID(of: "b", in: defaults), deployment)
    }

    func testAnOldEntryWithoutAMachineStillNamesTheServer() {
        let defaults = defaults()
        let deployment = UUID()
        defaults.set(["old": deployment.uuidString], forKey: "push.relayServers")
        XCTAssertEqual(RelayServers.target(of: "old", in: defaults)?.deploymentID, deployment)
        XCTAssertNil(RelayServers.target(of: "old", in: defaults)?.host)
    }
}
