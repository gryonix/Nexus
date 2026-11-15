import VPNTunnel
import XCTest

@testable import gryonixNexus

final class WidgetPushTests: XCTestCase {
    func testASummaryFillsTheReadingsAndKeepsTheRest() {
        var server = FleetSnapshot.Server(id: UUID(), name: "orion",
                                          updates: .init(waiting: 2, checked: 5, lastRunOnServer: nil, takenAt: Date()))
        let gnx: [String: Any] = [
            "kind": "gnx.widgets",
            "services": ["total": 9, "attention": 1],
            "backups": ["on": true, "every_days": 1, "services": 3, "retention": 7],
            "metrics": ["cpu": 12.5, "mem_used": 1, "mem_total": 4, "disk_used": 5, "disk_total": 10],
        ]
        WidgetPush.apply(gnx, at: Date(timeIntervalSince1970: 100), to: &server)
        XCTAssertEqual(server.services?.needingAttention, 1)
        XCTAssertEqual(server.backups?.everyDays, 1)
        XCTAssertEqual(server.metrics?.diskPercent, 50)
        XCTAssertNil(server.security)
        XCTAssertEqual(server.updates?.waiting, 2, "a push without updates keeps the app's reading")
    }

    func testAPushFromAnUnknownServerIsIgnored() {
        XCTAssertFalse(WidgetPush.received(["gnx": ["kind": "gnx.widgets", "server_id": "nobody"]]))
        XCTAssertFalse(WidgetPush.received(["gnx": ["kind": "gnx.alert.raid"]]))
    }
}
