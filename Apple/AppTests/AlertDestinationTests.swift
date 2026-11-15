import XCTest

@testable import gryonixNexus
import AgentControl
import ServiceCatalog

/// A tapped alert opens its server on the right section
final class AlertDestinationTests: XCTestCase {
    private let server = UUID()

    private func destination(_ kind: String, serverID: String = "srv") -> AlertDestination? {
        AlertDestination(gnx: ["server_id": serverID, "kind": kind]) { $0 == "srv" ? self.server : nil }
    }

    func testAServiceAlertOpensApps() {
        XCTAssertEqual(destination("gnx.alert.service"), AlertDestination(tab: .operations, deploymentID: server))
        XCTAssertEqual(destination("gnx.alert.service.ok")?.tab, .operations)
        XCTAssertEqual(destination("gnx.alert.backup")?.tab, .operations)
        XCTAssertEqual(destination("gnx.alert.drive_stale")?.tab, .operations)
    }

    func testDiskAgentAndSignInAlertsOpenGeneral() {
        for kind in ["gnx.alert.raid", "gnx.alert.smart", "gnx.alert.space", "gnx.alert.agent_update",
                     "gnx.alert.ssh_login", "gnx.alert.operation"] {
            XCTAssertEqual(destination(kind)?.tab, .general, kind)
        }
    }

    func testAnUnknownServerOpensNothing() {
        XCTAssertNil(destination("gnx.alert.service", serverID: "gone"))
        XCTAssertNil(AlertDestination(gnx: ["kind": "gnx.alert.service"]) { _ in self.server })
    }

    func testRunStartsAndEndsStayQuietInTheOpenApp() {
        XCTAssertTrue(ForegroundNotifications.isRunReport(["kind": "gnx.alert.operation.started"]))
        XCTAssertTrue(ForegroundNotifications.isRunReport(["kind": "gnx.alert.operation.failed"]))
        XCTAssertFalse(ForegroundNotifications.isRunReport(["kind": "gnx.alert.raid"]))
        XCTAssertFalse(ForegroundNotifications.isRunReport(nil))
    }
}

/// What a finding says to the user
final class HostFindingTextTests: XCTestCase {
    private func finding(_ code: String, args: [String], blocking: Bool, _ service: ServiceID = .odio) -> InstallFinding {
        InstallFinding(service: service, isBlocking: blocking, code: code, args: args, message: "english")
    }

    func testEachKnownCodeNamesTheServiceAndTheSystem() {
        let old = HostFindingText.text(finding("reduced_on_older_os", args: ["Debian 12", "Snapcast"], blocking: false))
        XCTAssertTrue(old.contains("Debian 12") && old.contains("Snapcast"), old)
        let newer = HostFindingText.text(finding("needs_newer_os", args: ["Debian 12", "Debian 13"], blocking: true, .mympd))
        XCTAssertTrue(newer.contains("Debian 13") && newer.contains("Debian 12"), newer)
        XCTAssertFalse(HostFindingText.text(finding("no_sound_card", args: [], blocking: true)).isEmpty)
    }

    func testAnUnknownCodeFallsBackToTheAgentsWording() {
        XCTAssertEqual(HostFindingText.text(finding("something_new", args: [], blocking: true)), "english")
    }

    func testOnlyBlockingFindingsBlockAService() {
        let findings = [finding("reduced_on_older_os", args: ["a", "b"], blocking: false),
                        finding("needs_newer_os", args: ["a", "b"], blocking: true, .mympd)]
        XCTAssertEqual(HostCompatibilitySection.blocked(findings), [.mympd])
    }
}
