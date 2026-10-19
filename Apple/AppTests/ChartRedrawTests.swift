import ServerControl
import XCTest

@testable import gryonixNexus

@MainActor
final class ChartRedrawTests: XCTestCase {
    private func point(_ offset: TimeInterval, cpu: Double) -> MetricsHistoryPoint {
        MetricsHistoryPoint(date: Date(timeIntervalSince1970: 1_000_000 + offset),
                            cpuPercent: cpu,
                            memUsedBytes: 512, memTotalBytes: 1024,
                            diskUsedBytes: 10, diskTotalBytes: 100,
                            netReceivedPerSecond: nil, netSentPerSecond: nil,
                            diskReadPerSecond: nil, diskWrittenPerSecond: nil,
                            load1: 0.2, temperatureCelsius: nil)
    }

    private func chart(points: [MetricsHistoryPoint] = [],
                       metrics: [HistoryMetric] = [.cpu],
                       range: HistoryRange = .hour,
                       legend: Bool = true) -> HistoryChart {
        HistoryChart(points: points, metrics: metrics, range: range, showsLegend: legend)
    }

    func testAChartHandedTheSameThingTwiceDoesNotRedraw() {
        let points = [point(0, cpu: 4), point(60, cpu: 9)]
        XCTAssertEqual(chart(points: points), chart(points: points))
    }

    /// Everything it plots, one per line
    func testEverythingItPlotsMakesItRedraw() {
        XCTAssertNotEqual(chart(), chart(points: [point(0, cpu: 4)]),
                          "the first reading arriving is the whole point")
        XCTAssertNotEqual(chart(points: [point(0, cpu: 4)]),
                          chart(points: [point(0, cpu: 5)]),
                          "same count, same timestamp, one value moved")
        XCTAssertNotEqual(chart(points: [point(0, cpu: 4)]),
                          chart(points: [point(0, cpu: 4), point(60, cpu: 4)]),
                          "a sample appended")
        XCTAssertNotEqual(chart(metrics: [.cpu]), chart(metrics: [.cpu, .memory]),
                          "a series added is a different plot")
        XCTAssertNotEqual(chart(range: .hour), chart(range: .day),
                          "the period is the x axis and the window on the data")
        XCTAssertNotEqual(chart(legend: true), chart(legend: false))
    }

    func testTheCoalescedWriteStillLandsWhenTheAppIsLeaving() {
        let defaults = UserDefaults(suiteName: "metrics.panels.flush.test")!
        defaults.removePersistentDomain(forName: "metrics.panels.flush.test")
        let store = MetricPanelStore(defaults: defaults)
        let panel = MetricPanel(deploymentID: UUID(), host: .vps, metrics: [.cpu], range: .hour)

        store.add(panel)
        // Nothing on disk yet: the write is deferred by design.
        store.flush()

        let reread = MetricPanelStore(defaults: defaults)
        XCTAssertEqual(reread.panels.map(\.id), [panel.id],
                       "a deferred write that never lands is a lost panel")
    }
}
