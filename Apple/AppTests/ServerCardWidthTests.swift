import ServerControl
import SwiftUI
import XCTest

@testable import gryonixNexus

@MainActor
final class ServerCardWidthTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await DemoFleetState.shared.forgetEverything()
    }

    private static let innerWidths: [CGFloat] = [320, 375, 390].map { $0 - 32 - 28 }

    private func sample(_ deployment: Deployment) -> ServerHostMetricsState {
        ServerHostMetricsState(snapshot: DemoHostMetrics.snapshot(
            deploymentID: deployment.id, host: .vps, tick: 720))
    }

    func testNoIndicatorStyleMakesACardWiderThanItsRow() {
        for deployment in DemoServer.deployments() {
            for style in MetricsIndicatorStyle.allCases {
                var styled = deployment
                styled.metricsIndicatorStyle = style
                let card = ServerMetricsCard(deployment: styled, host: .vps,
                                             state: sample(deployment))
                for inner in Self.innerWidths {
                    let demanded = width(of: card, proposing: inner)
                    XCTAssertLessThanOrEqual(
                        demanded, inner + 0.5,
                        "\(deployment.name) / \(style.rawValue) at \(inner)pt wants \(demanded)pt")
                }
            }
        }
    }

    func testTheTwoMachineCardFitsToo() {
        let deployment = DemoServer.relayPair()
        for style in MetricsIndicatorStyle.allCases {
            var styled = deployment
            styled.metricsIndicatorStyle = style
            let card = CombinedServerCard(
                deployment: styled,
                machines: deployment.nodes.map {
                    (host: $0.sshHost,
                     state: ServerHostMetricsState(snapshot: DemoHostMetrics.snapshot(
                        deploymentID: deployment.id, host: $0.sshHost, tick: 720)))
                })
            for inner in Self.innerWidths {
                let demanded = width(of: card, proposing: inner)
                XCTAssertLessThanOrEqual(
                    demanded, inner + 0.5,
                    "\(style.rawValue) at \(inner)pt wants \(demanded)pt")
            }
        }
    }

    // MARK: - The first reading must not resize the card

    func testTheFirstReadingDoesNotResizeTheCard() {
        for deployment in DemoServer.deployments() {
            for style in MetricsIndicatorStyle.allCases {
                var styled = deployment
                styled.metricsIndicatorStyle = style
                let blank = ServerMetricsCard(deployment: styled, host: .vps,
                                              state: ServerHostMetricsState())
                let read = ServerMetricsCard(deployment: styled, host: .vps,
                                             state: sample(deployment))
                for inner in Self.innerWidths + [440 - 32 - 28] {
                    XCTAssertEqual(height(of: blank, proposing: inner),
                                   height(of: read, proposing: inner),
                                   accuracy: 0.5,
                                   "\(deployment.name) / \(style.rawValue) at \(inner)pt "
                                   + "changes height when the first reading lands")
                }
            }
        }
    }

    func testTheTrafficLineKeepsItsShapeWhateverItHolds() {
        func grid(_ up: Double?, _ down: Double?) -> TrafficGrid {
            TrafficGrid(rows: [.init(title: "Network", legend: .network, up: up, down: down),
                               .init(title: "Disk", legend: .disk, up: up, down: down)])
        }
        let blank = grid(nil, nil)
        let small = grid(12_500, 17_900)
        let widest = grid(1_073_000_000, 1_073_000_000)
        let narrowest = CGFloat(320 - 32 - 28) / 2
        let reference = height(of: widest, width: narrowest)
        XCTAssertGreaterThan(reference, 0)
        for (name, row) in [("blank", blank), ("small", small)] {
            XCTAssertEqual(height(of: row, width: narrowest), reference, accuracy: 0.5,
                           "a \(name) traffic line is a different height from a full one — "
                           + "the card changes size when a reading lands")
        }
        XCTAssertLessThanOrEqual(
            idealWidth(of: widest), CGFloat(440 - 32 - 28),
            "the widest readings ask for more width than the widest phone's card has")
        XCTAssertGreaterThan(
            idealWidth(of: widest), narrowest,
            "the worded line already fits half a 320pt row — then the arrow "
            + "fallback under it is never drawn, and this test says nothing "
            + "about which form the cards use")
    }

    private func height(of view: some View, width: CGFloat) -> CGFloat {
        let host = UIHostingController(
            rootView: view.frame(width: width).fixedSize(horizontal: false, vertical: true))
        host.view.backgroundColor = .clear
        return host.sizeThatFits(in: CGSize(width: width,
                                            height: .greatestFiniteMagnitude)).height
    }

    /// The width a view asks for when nothing constrains it
    private func idealWidth(of view: some View) -> CGFloat {
        let host = UIHostingController(rootView: view.fixedSize())
        host.view.backgroundColor = .clear
        return host.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                            height: CGFloat.greatestFiniteMagnitude)).width
    }

    private static let compactInnerWidths: [CGFloat] =
        [320, 375, 390].map { ($0 - 32 - 10) / 2 }

    func testNoIndicatorStyleMakesANarrowCardWiderThanItsHalfRow() {
        for deployment in DemoServer.deployments() {
            for style in MetricsIndicatorStyle.allCases {
                var styled = deployment
                styled.metricsIndicatorStyle = style
                let card = CompactServerCard(deployment: styled, host: .vps,
                                             state: sample(deployment))
                for inner in Self.compactInnerWidths {
                    let demanded = width(of: card, proposing: inner)
                    XCTAssertLessThanOrEqual(
                        demanded, inner + 0.5,
                        "\(deployment.name) / \(style.rawValue) at \(inner)pt wants \(demanded)pt")
                }
            }
        }
    }

    func testTheNarrowTwoMachineCardFitsToo() {
        let deployment = DemoServer.relayPair()
        for style in MetricsIndicatorStyle.allCases {
            var styled = deployment
            styled.metricsIndicatorStyle = style
            let card = CompactCombinedServerCard(
                deployment: styled,
                machines: deployment.nodes.map {
                    (host: $0.sshHost,
                     state: ServerHostMetricsState(snapshot: DemoHostMetrics.snapshot(
                        deploymentID: deployment.id, host: $0.sshHost, tick: 720)))
                })
            for inner in Self.compactInnerWidths {
                let demanded = width(of: card, proposing: inner)
                XCTAssertLessThanOrEqual(
                    demanded, inner + 0.5,
                    "\(style.rawValue) at \(inner)pt wants \(demanded)pt")
            }
        }
    }

    func testTheNarrowCardKeepsRoughlyTheWideCardsHeight() {
        for style in MetricsIndicatorStyle.allCases {
            var deployment = DemoServer.deployments()[0]
            deployment.metricsIndicatorStyle = style
            let state = sample(deployment)
            let wide = height(of: ServerMetricsCard(deployment: deployment, host: .vps,
                                                    state: state),
                              proposing: 390 - 32 - 28)
            let narrow = height(of: CompactServerCard(deployment: deployment, host: .vps,
                                                      state: state),
                                proposing: Self.compactInnerWidths[2])
            XCTAssertEqual(narrow, wide, accuracy: wide / 7,
                           "\(style.rawValue): wide \(wide)pt, narrow \(narrow)pt")
            XCTAssertLessThanOrEqual(narrow, wide + 0.5,
                                     "\(style.rawValue): the half-width card is the TALLER of "
                                     + "the two — \(narrow)pt against \(wide)")
        }
    }

    private func height(of view: some View, proposing width: CGFloat) -> CGFloat {
        let host = UIHostingController(rootView: view.fixedSize(horizontal: false, vertical: true))
        host.view.backgroundColor = .clear
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    func testTheTrafficLineNeverAsksForMoreWidthThanItIsOffered() {
        func rows(_ up: Double?, _ down: Double?) -> [TrafficGrid.Row] {
            [.init(title: "Network", legend: .network, up: up, down: down),
             .init(title: "Disk", legend: .disk, up: up, down: down)]
        }
        var readings: [(String, [TrafficGrid.Row])] = [
            ("blank", rows(nil, nil)),
            ("small", rows(12_500, 17_900)),
            ("widest", rows(1_073_000_000, 1_073_000_000))]
        for deployment in DemoServer.deployments() {
            readings.append((deployment.name, TrafficGrid.rows(
                for: DemoHostMetrics.snapshot(deploymentID: deployment.id,
                                              host: .vps, tick: 720))))
        }
        for (name, row) in readings {
            for compact in [true, false] {
                let line = TrafficGrid(rows: row, compact: compact)
                for offered in stride(from: CGFloat(90), through: 400, by: 1) {
                    XCTAssertLessThanOrEqual(
                        width(of: line, proposing: offered), offered + 0.5,
                        "\(name), \(compact ? "compact" : "wide") at \(offered)pt wants "
                        + "\(width(of: line, proposing: offered))pt")
                }
            }
        }
    }

    private func width(of view: some View, proposing width: CGFloat) -> CGFloat {
        let host = UIHostingController(rootView: view)
        host.view.backgroundColor = .clear
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).width
    }
}
