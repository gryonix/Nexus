import UIKit
import XCTest

@testable import gryonixNexus

@MainActor
final class TabBarLongPressMenuTests: XCTestCase {
    private var previousStyle: BarStyle = .custom

    override func setUp() async throws {
        try await super.setUp()
        previousStyle = TabBarSettings.shared.barStyle
        TabBarSettings.shared.barStyle = .system
        let deadline = Date().addingTimeInterval(20)
        while MenuInstaller.tabBar() == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    override func tearDown() async throws {
        TabBarSettings.shared.barStyle = previousStyle
        try await super.tearDown()
    }

    func testTheInstallerFindsTheTabBarOfTheRunningApp() {
        XCTAssertNotNil(MenuInstaller.tabBar(),
                        "no UITabBar was found in the key window — the menu would hang on nothing")
    }

    func testTheButtonsOfTheRunningBarAreFound() {
        guard let bar = MenuInstaller.tabBar() else {
            return XCTFail("no UITabBar in the key window")
        }
        let slots = TabBarMenuPresenter.tabSlots(in: bar)
        XCTAssertGreaterThanOrEqual(slots.count, 2,
                                    "found \(slots.count) buttons on a real bar — the press can "
                                    + "name no tab, and every menu is the bar menu")
        XCTAssertEqual(slots.count, bar.items?.count ?? slots.count,
                       "\(slots.count) buttons for \(bar.items?.count ?? -1) items")
        for (left, right) in zip(slots, slots.dropFirst()) {
            XCTAssertLessThan(left.frame.midX, right.frame.midX,
                              "buttons \(left.frame) and \(right.frame) are out of order")
        }
        for slot in slots {
            XCTAssertTrue(bar.bounds.insetBy(dx: -1, dy: -1).contains(slot.frame),
                          "button \(slot.frame) is not inside the bar \(bar.bounds)")
        }
    }

    func testEveryButtonAnswersWithTheSectionItsLabelNames() {
        guard let bar = MenuInstaller.tabBar() else {
            return XCTFail("no UITabBar in the key window")
        }
        let slots = TabBarMenuPresenter.tabSlots(in: bar)
        let items = bar.items ?? []
        XCTAssertEqual(slots.count, items.count)
        for (index, slot) in slots.enumerated() where index < items.count {
            XCTAssertEqual(slot.title, items[index].title,
                           "button \(index) says \(slot.title ?? "nothing") while the bar's item "
                           + "says \(items[index].title ?? "nothing")")
            let press = CGPoint(x: slot.frame.midX, y: slot.frame.midY)
            let answered = TabBarMenuPresenter.tab(at: press, slots: slots)
            if let title = slot.title, let named = TabBarMenuPresenter.tab(named: title) {
                XCTAssertEqual(answered, named,
                               "holding \(title) offers \(answered?.rawValue ?? "the bar menu")")
            } else {
                // The "More" slot names no section of its own.
                XCTAssertNil(answered)
            }
        }

        let unresolved = slots.enumerated().filter {
            TabBarMenuPresenter.tab(named: $0.element.title ?? "") == nil
        }
        XCTAssertLessThanOrEqual(unresolved.count, 1,
                                 "\(unresolved.count) of \(slots.count) buttons name no section: "
                                 + "\(unresolved.map { $0.element.title ?? "nothing" })")
        if let only = unresolved.first {
            XCTAssertEqual(only.offset, slots.count - 1,
                           "button \(only.offset) (\(only.element.title ?? "nothing")) names no "
                           + "section, and it is not the overflow slot")
        }
    }

    /// Twice must not mean two menus
    func testInstallingTwiceLeavesOneGesture() {
        let bar = UITabBar()
        let first = MenuInstaller()
        XCTAssertTrue(first.install(on: bar))
        XCTAssertTrue(MenuInstaller().install(on: bar))
        let ours = (bar.gestureRecognizers ?? []).filter { $0.delegate is TabBarMenuPresenter }
        XCTAssertEqual(ours.count, 1,
                       "the bar carries \(ours.count) menu gestures, so a press opens that many")
        XCTAssertTrue(MenuInstaller.isInstalled(on: bar))
    }

    func testTheGestureIsAHoldAndOutlivesTheInstaller() {
        let bar = UITabBar()
        MenuInstaller().install(on: bar)
        let press = (bar.gestureRecognizers ?? [])
            .compactMap { $0 as? UILongPressGestureRecognizer }
            .first { $0.delegate is TabBarMenuPresenter }
        XCTAssertNotNil(press, "the bar carries no live long press — nothing opens the menu")
        XCTAssertGreaterThanOrEqual(press?.minimumPressDuration ?? 0, 0.3)
        XCTAssertNotNil(MenuInstaller.presenter(on: bar), "the bar lost its presenter")
        XCTAssertTrue(MenuInstaller.isInstalled(on: bar))
    }

    func testTheLookupReachesNestedButtonsAndDropsTheDuplicateSet() {
        let bar = UITabBar(frame: CGRect(x: 0, y: 0, width: 440, height: 83))
        let platter = UIView(frame: CGRect(x: 20, y: 0, width: 400, height: 62))
        bar.addSubview(platter)
        for offset in [CGFloat(0), 3] {
            let container = UIView(frame: platter.bounds)
            platter.addSubview(container)
            for i in 0..<4 {
                let button = StubTabButton(frame: CGRect(x: CGFloat(i) * 100 + offset, y: 4,
                                                         width: 84, height: 54))
                container.addSubview(button)
                button.addSubview(UIImageView(frame: button.bounds))
                let label = UILabel(frame: button.bounds)
                label.text = ["Servers", "Metrics", "VPN", "Terminal"][i]
                button.addSubview(label)
            }
        }

        let slots = TabBarMenuPresenter.tabSlots(in: bar)
        XCTAssertEqual(slots.count, 4, "got \(slots.count) slots for four tabs")
        XCTAssertEqual(slots.map(\.title), ["Servers", "Metrics", "VPN", "Terminal"])
        XCTAssertEqual(slots.first?.frame.minX ?? 0, 20, accuracy: 3.01)
    }

    func testTheTabUnderTheFingerIsTheOneTheMenuIsFor() {
        let titles = ["Servers", "Metrics", "VPN", "More"]
        let slots = (0..<4).map { i in
            TabBarMenuPresenter.Slot(frame: CGRect(x: CGFloat(i) * 100, y: 4,
                                                   width: 100, height: 54),
                                     title: titles[i])
        }

        XCTAssertEqual(TabBarMenuPresenter.tab(at: CGPoint(x: 50, y: 24), slots: slots), .servers)
        XCTAssertEqual(TabBarMenuPresenter.tab(at: CGPoint(x: 150, y: 24), slots: slots), .metrics)
        XCTAssertEqual(TabBarMenuPresenter.tab(at: CGPoint(x: 250, y: 24), slots: slots), .vpn)
        XCTAssertEqual(TabBarMenuPresenter.tab(at: CGPoint(x: 150, y: 78), slots: slots), .metrics)
        XCTAssertNil(TabBarMenuPresenter.tab(at: CGPoint(x: 350, y: 24), slots: slots))

        let real = [TabBarMenuPresenter.Slot(frame: CGRect(x: 25, y: 4, width: 84.6, height: 54),
                                             title: "Servers"),
                    TabBarMenuPresenter.Slot(frame: CGRect(x: 101.35, y: 4, width: 84.6, height: 54),
                                             title: "Metrics")]
        XCTAssertEqual(TabBarMenuPresenter.tab(at: CGPoint(x: 108, y: 30), slots: real), .metrics,
                       "the overlap band went to the tab beside the one held")
        XCTAssertEqual(TabBarMenuPresenter.tab(at: CGPoint(x: 103, y: 30), slots: real), .servers)
        XCTAssertEqual(TabBarMenuPresenter.tab(at: CGPoint(x: 10, y: 30), slots: real), .servers)
    }

    func testEverySectionIsFoundByItsOwnLabel() {
        for tab in AppTab.allCases {
            XCTAssertEqual(TabBarMenuPresenter.tab(named: tab.localizedTitle), tab,
                           "\(tab.rawValue) is drawn as \(tab.localizedTitle) and matches nothing")
        }
        XCTAssertNil(TabBarMenuPresenter.tab(named: "More"),
                     "the overflow slot was read as a section")
        XCTAssertNil(TabBarMenuPresenter.tab(named: " "))
    }

    func testTheAnchorIsAStripAboveTheHeldTab() {
        let bounds = CGRect(x: 0, y: 0, width: 440, height: 83)
        let slots = (0..<4).map { CGRect(x: 20 + CGFloat($0) * 100, y: 4, width: 84, height: 54) }

        let second = TabBarMenuPresenter.anchorFrame(in: bounds, slots: slots,
                                                     pressedAt: CGPoint(x: 150, y: 30))
        XCTAssertEqual(second.minX, slots[1].minX, accuracy: 0.01,
                       "the menu is anchored over some other tab")
        XCTAssertEqual(second.width, slots[1].width, accuracy: 0.01)
        XCTAssertLessThan(second.minY, bounds.minY,
                          "the anchor is inside the bar — the menu sits on it")
        XCTAssertGreaterThan(second.minY, bounds.minY - 30,
                             "the anchor floats \(bounds.minY - second.minY)pt off the bar")
        XCTAssertLessThanOrEqual(second.height, 2,
                                 "the anchor is \(second.height)pt tall — the menu covers the bar")

        let first = TabBarMenuPresenter.anchorFrame(in: bounds, slots: slots,
                                                    pressedAt: CGPoint(x: 30, y: 30))
        XCTAssertEqual(first.minX, slots[0].minX, accuracy: 0.01)
        XCTAssertNotEqual(first.minX, second.minX, "two different tabs anchor in the same place")

        for x in [CGFloat(0), 8, 436, 440] {
            let frame = TabBarMenuPresenter.anchorFrame(in: bounds, slots: slots,
                                                        pressedAt: CGPoint(x: x, y: 40))
            XCTAssertGreaterThanOrEqual(frame.minX, bounds.minX,
                                        "a press at x=\(x) anchored at \(frame), past the edge")
            XCTAssertLessThanOrEqual(frame.maxX, bounds.maxX,
                                     "a press at x=\(x) anchored at \(frame), past the edge")
        }
    }

    func testWithoutAPressTheAnchorSitsInTheMiddle() {
        let bounds = CGRect(x: 0, y: 0, width: 440, height: 83)
        let frame = TabBarMenuPresenter.anchorFrame(in: bounds, slots: [], pressedAt: nil)
        XCTAssertEqual(frame.midX, bounds.midX, accuracy: 0.01)
        XCTAssertLessThan(frame.minY, bounds.minY)
        XCTAssertGreaterThanOrEqual(frame.minX, bounds.minX)
        XCTAssertLessThanOrEqual(frame.maxX, bounds.maxX)
    }

    func testEveryHoldAnchorsToAFreshButtonOverTheTabHeld() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 440, height: 956))
        window.isHidden = false
        let bar = UITabBar(frame: CGRect(x: 0, y: 873, width: 440, height: 83))
        window.addSubview(bar)
        let container = UIView(frame: bar.bounds)
        bar.addSubview(container)
        let titles = ["Servers", "Metrics", "Containers"]
        for (index, title) in titles.enumerated() {
            let button = StubTabButton(frame: CGRect(x: CGFloat(index) * 140 + 20, y: 4,
                                                     width: 100, height: 54))
            container.addSubview(button)
            let label = UILabel(frame: button.bounds)
            label.text = title
            button.addSubview(label)
        }
        MenuInstaller().install(on: bar)
        guard let presenter = MenuInstaller.presenter(on: bar) else {
            return XCTFail("the bar carries no presenter")
        }

        let slots = TabBarMenuPresenter.tabSlots(in: bar)
        XCTAssertEqual(slots.count, 3)

        presenter.present(in: bar, at: CGPoint(x: slots[0].frame.midX, y: 30))
        guard let first = Self.anchor(on: bar) else {
            return XCTFail("the first hold left no anchor on the bar")
        }
        let firstFrame = first.frame
        XCTAssertEqual(firstFrame.minX, slots[0].frame.minX, accuracy: 0.01)

        presenter.present(in: bar, at: CGPoint(x: slots[2].frame.midX, y: 30))
        guard let second = Self.anchor(on: bar) else {
            return XCTFail("the second hold left no anchor on the bar")
        }
        XCTAssertFalse(second === first,
                       "the second hold reused the first hold's button, and UIKit places the "
                       + "menu where that button was when it first opened one")
        XCTAssertEqual(second.frame.minX, slots[2].frame.minX, accuracy: 0.01)
        XCTAssertNotEqual(second.frame.minX, firstFrame.minX,
                          "two different tabs anchored in the same place")
        XCTAssertEqual(Self.anchors(on: bar).count, 1,
                       "the bar carries \(Self.anchors(on: bar).count) anchors")
        XCTAssertNil(first.superview, "the replaced anchor is still on the bar")
    }

    private static func anchors(on bar: UITabBar) -> [UIButton] {
        bar.subviews.compactMap { $0 as? UIButton }
    }

    private static func anchor(on bar: UITabBar) -> UIButton? { anchors(on: bar).last }

    private final class StubTabButton: UIView {}
}
