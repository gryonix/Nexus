import ServerControl
import SwiftUI
import XCTest
@testable import gryonixNexus

final class PairContextMenuTargetTests: XCTestCase {
    func testARowOfTwoCardsCarriesOneMenuForBoth() {
        let host = UIHostingController(rootView: Probe())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        host.view.layoutIfNeeded()

        var found: [(CGRect, String)] = []
        collect(host.view, into: &found)
        let reported = found.map { "\($0.1) \($0.0)" }.joined(separator: ", ")
        XCTAssertEqual(found.count, 1,
                       "the row's menu is one interaction, not one per card: \(reported)")
        XCTAssertEqual(found.first?.0.width, 400, "the interaction belongs to the list itself")
    }

    @MainActor
    func testTheMenuIsBuiltForTheCardThatWasPressed() {
        let left = DemoServer.deployment()
        let right = DemoServer.relayPair()
        let row = [left, right]
        let tracker = CardPressTracker()

        XCTAssertEqual(tracker.target(in: row, fallback: left).id, left.id,
                       "with nothing pressed the menu is the card that declared it")

        tracker.press(right.id)
        XCTAssertEqual(tracker.target(in: row, fallback: left).id, right.id,
                       "the right card was held, so the menu is the right card's")

        tracker.press(left.id)
        XCTAssertEqual(tracker.target(in: row, fallback: right).id, left.id)

        tracker.press(UUID())
        XCTAssertEqual(tracker.target(in: row, fallback: right).id, right.id,
                       "an id from another row falls back to the declaring card")
    }

    func testTheCardIsHandedTheWholeRow() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/Features/Servers/ServerListView.swift"),
                                encoding: .utf8)
        XCTAssertTrue(source.contains("card(for: deployment, in: row.all)"),
                      "the card is resolving its menu against something other than the whole row; "
                      + "a row carries ONE menu, so the row is the only set the press may name")
    }

    @MainActor
    func testACardInTheSecondColumnIsItsOwnMenusTarget() {
        let tall = DemoServer.relayPair()          // two machines: two slots
        let first = DemoServer.deployment()
        let second = DemoServer.localOnly()
        let packed = ServerCardLayout.rows(of: [tall, first, second], whenUnset: .compact)
        guard let row = packed.first, row.columns.count == 2 else {
            return XCTFail("the fleet did not pack into a row of two columns: \(packed)")
        }
        guard let rightHand = row.columns[1].first else { return XCTFail("empty second column") }

        let tracker = CardPressTracker()
        tracker.press(rightHand.id)
        XCTAssertEqual(tracker.target(in: row.all, fallback: row.all[0]).id, rightHand.id,
                       "the card held in the second column must be the menu's own target")
    }

    private func collect(_ view: UIView, into found: inout [(CGRect, String)]) {
        for interaction in view.interactions where interaction is UIContextMenuInteraction {
            found.append((view.convert(view.bounds, to: nil), String(describing: type(of: view))))
        }
        for sub in view.subviews { collect(sub, into: &found) }
    }

    private struct Probe: View {
        var body: some View {
            List {
                Grid(horizontalSpacing: 10, verticalSpacing: 0) {
                    GridRow {
                        cell("left")
                        cell("right")
                    }
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
        }

        private func cell(_ name: String) -> some View {
            Button {} label: {
                Color.gray.frame(height: 120).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(name) {}
            }
            .frame(maxWidth: .infinity)
        }
    }
}
