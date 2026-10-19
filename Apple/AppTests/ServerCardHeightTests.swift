import ServerControl
import SwiftUI
import XCTest

@testable import gryonixNexus

@MainActor
final class ServerCardHeightTests: XCTestCase {
    private static let wideWidths: [CGFloat] = [320, 375, 390, 440].map { $0 - 32 - 28 }
    private static let compactWidths: [CGFloat] = [320, 375, 390, 440].map { ($0 - 32 - 10) / 2 }

    private func sample(_ deployment: Deployment,
                        _ host: SSHHostID = .vps) -> ServerHostMetricsState {
        ServerHostMetricsState(snapshot: DemoHostMetrics.snapshot(
            deploymentID: deployment.id, host: host, tick: 720))
    }

    // MARK: - One size per card, whatever the indicator

    func testEveryIndicatorStyleGivesTheWideCardOneHeight() {
        for deployment in DemoServer.deployments() {
            for width in Self.wideWidths {
                let heights = MetricsIndicatorStyle.allCases.map { style -> CGFloat in
                    var styled = deployment
                    styled.metricsIndicatorStyle = style
                    return height(of: ServerMetricsCard(deployment: styled, host: .vps,
                                                        state: sample(deployment)),
                                  proposing: width)
                }
                assertOneHeight(heights, "\(deployment.name) at \(width)pt")
            }
        }
    }

    func testEveryIndicatorStyleGivesTheNarrowCardOneHeight() {
        for deployment in DemoServer.deployments() {
            for width in Self.compactWidths {
                let heights = MetricsIndicatorStyle.allCases.map { style -> CGFloat in
                    var styled = deployment
                    styled.metricsIndicatorStyle = style
                    return height(of: CompactServerCard(deployment: styled, host: .vps,
                                                        state: sample(deployment)),
                                  proposing: width)
                }
                assertOneHeight(heights, "narrow \(deployment.name) at \(width)pt")
            }
        }
    }

    func testTheTwoMachineCardHasOneHeightToo() {
        let deployment = DemoServer.relayPair()
        for width in Self.wideWidths {
            let heights = MetricsIndicatorStyle.allCases.map { style -> CGFloat in
                var styled = deployment
                styled.metricsIndicatorStyle = style
                return height(of: CombinedServerCard(
                    deployment: styled,
                    machines: deployment.nodes.map {
                        (host: $0.sshHost, state: sample(deployment, $0.sshHost))
                    }), proposing: width)
            }
            assertOneHeight(heights, "two-machine card at \(width)pt")
        }
    }

    private func assertOneHeight(_ heights: [CGFloat], _ what: String) {
        let styles = MetricsIndicatorStyle.allCases.map(\.rawValue)
        let reported = zip(styles, heights).map { "\($0) \($1)pt" }.joined(separator: ", ")
        XCTAssertGreaterThan(heights.first ?? 0, 0, what)
        for height in heights.dropFirst() {
            XCTAssertEqual(height, heights[0], accuracy: 0.5, "\(what): \(reported)")
        }
    }

    func testTheWideBlockFitsEveryStylesRows() {
        let bars = idealHeight(of: GaugeRow(label: "Mem", detail: "6.1 G / 16 G",
                                            percent: 42.4, fraction: 0.424), width: 200)
        let line = idealHeight(of: GaugeRow(label: "Mem", detail: "6.1 G / 16 G",
                                            percent: 42.4, fraction: 0.424, track: true),
                               width: 200)
        let minimal = idealHeight(of: MinimalMetricRow(label: "Mem", percent: 42.4,
                                                       fraction: 0.424), width: 200)
        for (name, row) in [("bars", bars), ("line", line), ("minimal", minimal)] {
            assertBlockFits(row, gap: MetricBlock.wideGap, block: MetricBlock.wide, name)
        }
    }

    func testTheCompactBlockFitsEveryStylesRows() {
        let bars = idealHeight(of: CompactGaugeRow(label: "Mem", percent: 42.4,
                                                   fraction: 0.424), width: 120)
        let line = idealHeight(of: CompactGaugeRow(label: "Mem", percent: 42.4,
                                                   fraction: 0.424, track: true), width: 120)
        let minimal = idealHeight(of: CompactMinimalRow(label: "Mem", percent: 42.4,
                                                        fraction: 0.424), width: 120)
        for (name, row) in [("bars", bars), ("line", line), ("minimal", minimal)] {
            assertBlockFits(row, gap: MetricBlock.compactGap, block: MetricBlock.compact,
                            "narrow \(name)")
        }
    }

    private func assertBlockFits(_ row: CGFloat, gap: CGFloat, block: CGFloat,
                                 _ name: String) {
        let needed = row * 3 + gap * 2
        XCTAssertGreaterThan(row, 0, name)
        XCTAssertLessThanOrEqual(needed, block + 0.5,
                                 "\(name): three \(row)pt rows need \(needed)pt "
                                 + "of a \(block)pt block — they draw over the card's edge")
        XCTAssertGreaterThanOrEqual(needed, block - row,
                                    "\(name): three \(row)pt rows fill \(needed)pt of a "
                                    + "\(block)pt block — the rest of the card is a hole")
    }

    // MARK: - The rings and the room they are given

    func testARingNeverOverflowsTheBlockItIsDrawnIn() {
        for width in Self.wideWidths + [1024 - 32 - 28] {
            let diameter = ringDiameter(cardWidth: width)
            let drawn = idealHeight(of: RingGauge(label: "Mem", fraction: 0.42,
                                                  diameter: diameter),
                                    width: leftoverForRings(in: width) / 3)
            XCTAssertLessThanOrEqual(
                drawn, MetricBlock.wide + 0.5,
                "a \(diameter)pt ring draws \(drawn)pt of a \(MetricBlock.wide)pt block "
                + "at \(width)pt of card — over the edge of the card")
        }
    }

    func testTheRingFillsTheBlockOnEveryPhone() {
        let block = MetricBlock.wide - RingLayout.labelHeight
        for width in Self.wideWidths {
            XCTAssertEqual(ringDiameter(cardWidth: width), block, accuracy: 0.5,
                           "at \(width)pt of card the ring is \(ringDiameter(cardWidth: width))pt "
                           + "of a \(block)pt block")
        }
        let narrow: CGFloat = 3 * block - 30
        XCTAssertLessThan(ringDiameter(cardWidth: narrow), block - 1,
                          "at \(narrow)pt of card the width has to be what limits the ring")
    }

    func testAStretchedCardDoesNotDrawRingsOverEachOther() {
        let width: CGFloat = (1024 - 32 - 10) / 2 - 24
        let block = CGSize(width: width, height: 390)
        let cell = width / 3

        let sideBySide = RingLayout.diameter(in: block, count: 3,
                                             gutter: RingLayout.compactGutter,
                                             labelHeight: RingLayout.labelHeight, floor: 20,
                                             cap: RingLayout.compactMaxDiameter)
        XCTAssertLessThanOrEqual(
            sideBySide, cell,
            "three \(sideBySide)pt rings in cells of \(cell)pt draw over each other")

        let drawn = idealWidth(of: RingGauge(label: "Mem", fraction: 0.42,
                                             diameter: sideBySide))
        XCTAssertLessThanOrEqual(drawn, cell,
                                 "a \(sideBySide)pt ring draws \(drawn)pt wide")

        XCTAssertTrue(RingLayout.stacks(in: block, count: 3,
                                        gutter: RingLayout.compactGutter,
                                        stackedGutter: RingLayout.stackedGutter,
                                        labelHeight: RingLayout.labelHeight,
                                        labelWidth: RingLayout.trailingLabelWidth,
                                        floor: 20, cap: RingLayout.compactMaxDiameter),
                      "a card stretched to \(block.height)pt still draws its rings in a row")
    }

    func testTheWideCardsRingsAreCappedToo() {
        let width: CGFloat = 1024 - 32 - 28
        let diameter = RingLayout.diameter(in: CGSize(width: width, height: 390),
                                           count: 3, gutter: RingLayout.wideGutter,
                                           labelHeight: RingLayout.labelHeight, floor: 24,
                                           cap: RingLayout.wideMaxDiameter, outerAir: false)
        XCTAssertEqual(diameter, RingLayout.wideMaxDiameter, accuracy: 0.5,
                       "a block \(390)pt tall drew a \(diameter)pt ring")
    }

    private func ringDiameter(cardWidth: CGFloat) -> CGFloat {
        RingLayout.diameter(in: CGSize(width: leftoverForRings(in: cardWidth),
                                       height: MetricBlock.wide),
                            count: 3, gutter: RingLayout.wideGutter,
                            labelHeight: RingLayout.labelHeight, floor: 24,
                            cap: RingLayout.wideMaxDiameter,
                            outerAir: false)
    }

    private func leftoverForRings(in cardWidth: CGFloat) -> CGFloat { cardWidth }

    private func idealWidth(of view: some View) -> CGFloat {
        let host = UIHostingController(rootView: view.fixedSize())
        host.view.backgroundColor = .clear
        return host.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                            height: CGFloat.greatestFiniteMagnitude)).width
    }

    /// The height a row asks for when nothing stretches it
    private func idealHeight(of view: some View, width: CGFloat) -> CGFloat {
        let host = UIHostingController(
            rootView: view.frame(width: width).fixedSize(horizontal: false, vertical: true))
        host.view.backgroundColor = .clear
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    private func height(of view: some View, proposing width: CGFloat) -> CGFloat {
        let host = UIHostingController(rootView: view.fixedSize(horizontal: false, vertical: true))
        host.view.backgroundColor = .clear
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }
}
