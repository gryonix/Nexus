import ServerControl
import XCTest

@testable import gryonixNexus

/// The swap row on every server card
final class SwapCardRowTests: XCTestCase {
    private func snapshot(swapTotal: Int64, swapUsed: Int64) -> HostMetricsSnapshot {
        var sample = HostMetricsSample()
        sample.memTotalBytes = 8 << 30
        sample.swapTotalBytes = swapTotal
        sample.swapUsedBytes = swapUsed
        return HostMetricsSnapshot(current: sample, previous: nil)
    }

    func testSwapInUseShowsItsLoad() {
        let row = MetricDatum.swap(for: snapshot(swapTotal: 2 << 30, swapUsed: 1 << 29))
        XCTAssertEqual(row.fraction ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(row.percent ?? 0, 25, accuracy: 0.01)
    }

    func testNoSwapSaysOff() {
        let row = MetricDatum.swap(for: snapshot(swapTotal: 0, swapUsed: 0))
        XCTAssertNil(row.fraction)
        XCTAssertEqual(row.detail, UIL10n.string("Off"))
    }

    func testNoReadingYetIsADash() {
        XCTAssertEqual(MetricDatum.swap(for: nil).detail, "—")
    }

    func testEveryCardHasFourRows() {
        XCTAssertEqual(MetricDatum.all(for: nil).count, 4)
    }
}
