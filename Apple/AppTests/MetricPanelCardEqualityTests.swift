import ServerControl
import XCTest

@testable import gryonixNexus

@MainActor
final class MetricPanelCardEqualityTests: XCTestCase {
    private let deployment = Deployment(name: "example.net",
                                        topology: .singleHost,
                                        entry: HostEndpoint(host: "203.0.113.10", user: "root"))
    private lazy var panel = MetricPanel(deploymentID: deployment.id, host: .vps,
                                         metrics: [.cpu], range: .hour)

    private func card(panel: MetricPanel? = nil,
                      points: [MetricsHistoryPoint] = [],
                      error: String? = nil,
                      editable: Bool = true) -> MetricPanelCard {
        MetricPanelCard(panel: panel ?? self.panel,
                        deployment: deployment,
                        points: points,
                        errorMessage: error,
                        openHistory: {},
                        onEdit: editable ? {} : nil,
                        onDelete: editable ? {} : nil,
                        onMetrics: editable ? { _ in } : nil)
    }

    private func point(_ offset: TimeInterval, cpu: Double) -> MetricsHistoryPoint {
        MetricsHistoryPoint(date: Date(timeIntervalSince1970: 1_000_000 + offset),
                            cpuPercent: cpu,
                            memUsedBytes: 512, memTotalBytes: 1024,
                            diskUsedBytes: 10, diskTotalBytes: 100,
                            netReceivedPerSecond: nil, netSentPerSecond: nil,
                            diskReadPerSecond: nil, diskWrittenPerSecond: nil,
                            load1: 0.2, temperatureCelsius: nil)
    }

    func testTwoCardsBuiltFromTheSameValuesAreEqual() {
        XCTAssertEqual(card(), card())
    }

    func testFreshClosuresDoNotMakeACardUnequal() {
        var counter = 0
        let first = MetricPanelCard(panel: panel, deployment: deployment, points: [],
                                    errorMessage: nil, openHistory: { counter += 1 },
                                    onEdit: { counter += 2 }, onDelete: nil)
        let second = MetricPanelCard(panel: panel, deployment: deployment, points: [],
                                     errorMessage: nil, openHistory: { counter += 3 },
                                     onEdit: { counter += 4 }, onDelete: nil)
        XCTAssertEqual(first, second)
    }

    func testEverythingTheCardDrawsMakesItUnequal() {
        var other = panel
        other.metricsRaw = ["cpu", "memory"]
        XCTAssertNotEqual(card(), card(panel: other), "the metric set is the tile's title and its lines")

        var period = panel
        period.rangeRaw = HistoryRange.day.rawValue
        XCTAssertNotEqual(card(), card(panel: period), "the period is the x axis")

        XCTAssertNotEqual(card(), card(points: [point(0, cpu: 5)]),
                          "the first reading arriving is the whole point of the tile")
        XCTAssertNotEqual(card(points: [point(0, cpu: 5)]),
                          card(points: [point(0, cpu: 6)]),
                          "same count, same timestamp, different value — a cheaper comparison would miss it")
        XCTAssertNotEqual(card(points: [point(0, cpu: 5)]),
                          card(points: [point(0, cpu: 5), point(60, cpu: 5)]),
                          "a new sample appended")
        XCTAssertNotEqual(card(), card(error: "unreachable"),
                          "the failure line replaces the summary")
        XCTAssertNotEqual(card(), card(editable: false),
                          "an uneditable card draws no menu at all")

        let fixedMetrics = MetricPanelCard(panel: panel, deployment: deployment, points: [],
                                           errorMessage: nil, openHistory: {},
                                           onEdit: {}, onDelete: {}, onMetrics: nil)
        XCTAssertNotEqual(card(), fixedMetrics,
                          "the badge is a menu where the metrics can be chosen and a link where they cannot")
    }
}
