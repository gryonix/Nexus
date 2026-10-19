import ServerControl
import XCTest

@testable import gryonixNexus

@MainActor
final class OwnerReportedDefectsTests: XCTestCase {
    // MARK: - A hold is not a tap

    func testAHoldSuppressesTheTapThatWouldOpenTheServer() {
        let tracker = CardPressTracker()
        let id = UUID()

        tracker.press(id)
        XCTAssertFalse(tracker.wasHeld(id), "a quick tap is not a hold — the server must open")

        tracker.press(id)
        tracker.markHeld(id)
        XCTAssertTrue(tracker.wasHeld(id), "the finger stayed: this touch belongs to the menu")
        XCTAssertFalse(tracker.wasHeld(id),
                       "and it is consumed — the next tap opens the server as usual")
    }

    func testAFreshPressClearsAnOldHold() {
        let tracker = CardPressTracker()
        let id = UUID()
        tracker.press(id)
        tracker.markHeld(id)
        tracker.press(id)
        XCTAssertFalse(tracker.wasHeld(id), "a later tap must still open the server")
    }

    func testAHoldOnOneCardDoesNotSuppressTheOther() {
        let tracker = CardPressTracker()
        let held = UUID()
        let other = UUID()
        tracker.press(held)
        tracker.markHeld(held)
        XCTAssertFalse(tracker.wasHeld(other), "the other half of the row is still tappable")
        XCTAssertTrue(tracker.wasHeld(held))
    }

    /// The threshold is the system's own menu delay
    func testTheHoldThresholdIsTheSystemsMenuDelay() {
        XCTAssertEqual(ServerCardHold.menuDelay, 0.5, accuracy: 0.001)
    }

    // MARK: - A server that stopped answering shows no numbers

    func testAnUnreachableServerDrawsNoReadings() {
        var state = ServerHostMetricsState(snapshot: .sample(cpu: 15), errorMessage: nil)
        XCTAssertNotNil(state.liveSnapshot, "a server that answers shows what it answered")

        state.errorMessage = "Connection refused"
        XCTAssertNil(state.liveSnapshot,
                     "a server that has stopped answering must not show a reading as current")
        XCTAssertNotNil(state.snapshot,
                        "the last reading is still KEPT — what changed is that it is not drawn")
    }

    func testTheReadingsBecomeDashesRatherThanDisappearing() {
        let data = MetricDatum.all(for: nil)
        XCTAssertEqual(data.count, 3, "CPU, memory and disk keep their rows")
        XCTAssertTrue(data.allSatisfy { $0.percent == nil })
        XCTAssertTrue(data.allSatisfy { $0.detail == "—" })
    }
}

private extension HostMetricsSnapshot {
    static func sample(cpu: Double) -> HostMetricsSnapshot {
        HostMetricsSnapshot(collectorRow: MetricsHistoryPoint(
            date: Date(timeIntervalSince1970: 1_000_000),
            cpuPercent: cpu, memUsedBytes: 512, memTotalBytes: 1024,
            diskUsedBytes: 10, diskTotalBytes: 100,
            netReceivedPerSecond: 1, netSentPerSecond: 1,
            diskReadPerSecond: 1, diskWrittenPerSecond: 1,
            load1: 0.2, temperatureCelsius: nil))
    }
}
