import ServerControl
import XCTest

@testable import gryonixNexus

/// When a setting waits, and what a tapped alert opens
final class PendingRulesTests: XCTestCase {
    func testAChangedValueWaitsAndAnUntouchedOrEqualOneDoesNot() {
        XCTAssertTrue(PendingRules.waits(RebootSchedule.daily(hour: 4, minute: 0), saved: RebootSchedule.off))
        XCTAssertFalse(PendingRules.waits(RebootSchedule.off, saved: RebootSchedule.off))
        XCTAssertFalse(PendingRules.waits(nil as RebootSchedule?, saved: RebootSchedule.off), "no draft, nothing waits")
    }

    func testAnInvalidValueOrRunningWorkKeepsTheBarDown() {
        XCTAssertFalse(PendingRules.waits("b", saved: "a", valid: false))
        XCTAssertFalse(PendingRules.waits("b", saved: "a", busy: true))
        XCTAssertTrue(PendingRules.waits("b", saved: "a", valid: true, busy: false))
    }

    func testAHostNameWaitsOnlyWhenItIsValidAndNew() {
        XCTAssertTrue(PendingRules.hostName("draco", saved: "orion"))
        XCTAssertFalse(PendingRules.hostName("orion", saved: "orion"))
        XCTAssertFalse(PendingRules.hostName("Not A Name", saved: "orion"))
        XCTAssertFalse(PendingRules.hostName("", saved: "orion"))
    }

    func testABackupScheduleWaitsWhenChangedOrWhenAPassphraseIsTyped() {
        XCTAssertFalse(PendingRules.backupSchedule(canSave: true, changed: false, passphrase: ""))
        XCTAssertTrue(PendingRules.backupSchedule(canSave: true, changed: true, passphrase: ""))
        XCTAssertTrue(PendingRules.backupSchedule(canSave: true, changed: false, passphrase: "secret"))
        XCTAssertFalse(PendingRules.backupSchedule(canSave: false, changed: true, passphrase: "secret"))
    }

    private let server = UUID()

    private func tap(_ gnx: [String: Any], title: String = "Title") -> AlertTap {
        AlertTap(gnx: gnx, title: title, body: "Body") { $0 == "srv" ? self.server : nil }
    }

    func testAnAlertAboutARunOpensThatRunAndFallsBackToItsServer() {
        let found = tap(["server_id": "srv", "kind": "gnx.alert.operation.failed", "job_id": "job-1"])
        guard case .run(let jobID, let fallback, let card) = found else { return XCTFail("\(found)") }
        XCTAssertEqual(jobID, "job-1")
        XCTAssertEqual(fallback?.deploymentID, server)
        XCTAssertNil(card)
    }

    func testAnEmptyRunIdIsNotARun() {
        let found = tap(["server_id": "srv", "kind": "gnx.alert.operation", "job_id": ""])
        XCTAssertEqual(found, .server(AlertDestination(tab: .general, deploymentID: server)))
    }

    func testAProblemAlertOpensItsCard() {
        let found = tap(["server_id": "srv", "kind": "gnx.alert.space"], title: "Disk almost full")
        guard case .card(let destination, let card) = found else { return XCTFail("\(found)") }
        XCTAssertEqual(destination.deploymentID, server)
        XCTAssertEqual(card.title, "Disk almost full")
    }

    func testOtherAlertsOpenTheServerAndAnUnknownServerOpensNothing() {
        XCTAssertEqual(tap(["server_id": "srv", "kind": "gnx.alert.ssh_login"]),
                       .server(AlertDestination(tab: .general, deploymentID: server)))
        XCTAssertEqual(tap(["server_id": "gone", "kind": "gnx.alert.ssh_login"]), .nothing)
        XCTAssertEqual(tap(["server_id": "gone", "kind": "gnx.alert.space"]), .nothing,
                       "a card needs a server to open over")
    }
}
