import XCTest

@testable import gryonixNexus

@MainActor
final class SectionReorderTests: XCTestCase {
    private func settings(_ name: String) -> TabBarSettings {
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return TabBarSettings(defaults: store)
    }

    // MARK: - One step at a time

    func testMovingASectionDownSwapsItWithTheOneBelow() {
        let tabs = settings("tabs.reorder.down")
        let before = tabs.order
        let moved = before[1]
        let displaced = before[2]

        tabs.moveDown(moved)

        XCTAssertEqual(tabs.order[1], displaced)
        XCTAssertEqual(tabs.order[2], moved)
        XCTAssertEqual(Set(tabs.order), Set(before), "a move is a reorder, not an edit")
        XCTAssertEqual(tabs.order.count, before.count)
    }

    func testMovingASectionUpSwapsItWithTheOneAbove() {
        let tabs = settings("tabs.reorder.up")
        let before = tabs.order
        let moved = before[2]
        let displaced = before[1]

        tabs.moveUp(moved)

        XCTAssertEqual(tabs.order[1], moved)
        XCTAssertEqual(tabs.order[2], displaced)
        XCTAssertEqual(tabs.order.suffix(from: 3), before.suffix(from: 3),
                       "the rest of the bar stays where it was")
    }

    func testTheEndsOfTheListDoNotMove() {
        let tabs = settings("tabs.reorder.ends")
        let before = tabs.order

        tabs.moveUp(before.first!)
        XCTAssertEqual(tabs.order, before)

        tabs.moveDown(before.last!)
        XCTAssertEqual(tabs.order, before)
    }

    /// What the buttons are disabled by
    func testTheArrowsAreOfferedExactlyWhereTheyDoSomething() {
        let tabs = settings("tabs.reorder.enabled")
        let order = tabs.order

        XCTAssertFalse(tabs.canMoveUp(order.first!))
        XCTAssertTrue(tabs.canMoveDown(order.first!))
        XCTAssertTrue(tabs.canMoveUp(order.last!))
        XCTAssertFalse(tabs.canMoveDown(order.last!))
    }

    func testAMoveIsWrittenDown() {
        let name = "tabs.reorder.persist"
        let tabs = settings(name)
        let moved = tabs.order[0]
        tabs.moveDown(moved)
        let expected = tabs.order

        XCTAssertEqual(TabBarSettings(defaults: UserDefaults(suiteName: name)!).order, expected)
    }

    // MARK: - The numbers the macOS menu uses

    func testTheNumberedSectionsAreTheOnesOnTheBar() {
        let tabs = settings("tabs.sections.filter")
        let order = tabs.visibleTabs

        let withMetrics = ShellSections.visible(order: order,
                                                metricsRaw: MetricsPlacement.both.rawValue,
                                                vpnRaw: VPNPlacement.both.rawValue,
                                                containersRaw: ContainersPlacement.both.rawValue,
                                                terminalRaw: TerminalPlacement.both.rawValue)
        let withoutMetrics = ShellSections.visible(order: order,
                                                   metricsRaw: MetricsPlacement.server.rawValue,
                                                   vpnRaw: VPNPlacement.both.rawValue,
                                                   containersRaw: ContainersPlacement.both.rawValue,
                                                   terminalRaw: TerminalPlacement.both.rawValue)

        XCTAssertTrue(withMetrics.contains(.metrics))
        XCTAssertFalse(withoutMetrics.contains(.metrics),
                       "a section that lives inside a server only is not on the bar to be numbered")
        XCTAssertEqual(withoutMetrics, withMetrics.filter { $0 != .metrics },
                       "and nothing else moves out of the user's order")
    }

    func testTheSectionsThatStartInsideAServerAreNotNumbered() {
        let tabs = settings("tabs.sections.defaults")
        let sections = ShellSections.visible(order: tabs.visibleTabs,
                                             metricsRaw: MetricsPlacement.both.rawValue,
                                             vpnRaw: VPNPlacement.both.rawValue,
                                             containersRaw: ContainersPlacement.server.rawValue,
                                             terminalRaw: TerminalPlacement.server.rawValue)

        XCTAssertFalse(sections.contains(.containers))
        XCTAssertFalse(sections.contains(.terminal))
        XCTAssertTrue(sections.contains(.servers))
        XCTAssertTrue(sections.contains(.settings), "settings can never be hidden — ⌘, always lands")
    }

    func testReorderingTheBarRenumbersTheShortcuts() {
        let tabs = settings("tabs.sections.renumber")
        let first = tabs.visibleTabs[0]
        let second = tabs.visibleTabs[1]

        tabs.moveUp(second)

        let sections = ShellSections.visible(order: tabs.visibleTabs,
                                             metricsRaw: MetricsPlacement.both.rawValue,
                                             vpnRaw: VPNPlacement.both.rawValue,
                                             containersRaw: ContainersPlacement.both.rawValue,
                                             terminalRaw: TerminalPlacement.both.rawValue)
        XCTAssertEqual(sections.first, second, "⌘1 follows the bar, not the enum")
        XCTAssertEqual(sections[1], first)
    }
}
