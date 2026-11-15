import XCTest

@testable import gryonixNexus

/// A tapped alert about a problem gets a card
final class AlertCardTests: XCTestCase {
    private func card(_ kind: String, title: String = "Disk almost full on orion") -> AlertCard? {
        AlertCard(gnx: ["kind": kind, "server_id": "srv"], title: title, body: "/ is 93% full.")
    }

    func testEveryProblemKindHasACardWithAdvice() {
        for kind in ["raid", "smart", "space", "backup", "drive_stale", "drive_readonly", "load", "memory"] {
            let found = card("gnx.alert.\(kind)")
            XCTAssertNotNil(found, kind)
            XCTAssertFalse(found?.advice?.isEmpty ?? true, kind)
        }
    }

    func testTheCardKeepsTheAlertsOwnWords() {
        let found = card("gnx.alert.space")
        XCTAssertEqual(found?.title, "Disk almost full on orion")
        XCTAssertEqual(found?.body, "/ is 93% full.")
    }

    func testRecoveriesSignInsRunsAndServicesGetNoCard() {
        for kind in ["gnx.alert.space.ok", "gnx.alert.ssh_login", "gnx.alert.agent_update", "gnx.alert.test",
                     "gnx.alert.operation.failed", "gnx.alert.service", ""] {
            XCTAssertNil(card(kind), kind)
        }
    }

    func testAnAlertWithoutATitleGetsNoCard() {
        XCTAssertNil(card("gnx.alert.space", title: ""))
    }

    func testAdviceNamesTheScreenToOpen() {
        XCTAssertFalse(AlertCard.advice(forKind: "gnx.alert.raid")?.contains("%@") ?? true)
        XCTAssertFalse(AlertCard.advice(forKind: "gnx.alert.load")?.contains("%@") ?? true)
    }
}
