import XCTest

@testable import gryonixNexus

@MainActor
final class SectionPlacementTests: XCTestCase {
    private func defaults(_ name: String) -> UserDefaults {
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    /// The bar somebody who has never touched it gets
    func testTheDefaultOrderIsTheOneTheOwnerAskedFor() {
        XCTAssertEqual(TabBarSettings(defaults: defaults("tabs.order.test")).order,
                       [.servers, .metrics, .containers, .vpn, .terminal, .configurator, .settings],
                       "servers, metrics, vpn, terminal, configurator, settings — containers rides beside metrics, and both it and terminal are hidden by their placement, not by their position")
    }

    func testAnUntouchedOldOrderIsBroughtForwardWholesale() {
        let store = defaults("tabs.reconcile.test")
        store.set(["servers", "metrics", "vpn", "configurator", "settings"], forKey: "tabs.order")
        XCTAssertEqual(TabBarSettings(defaults: store).order, AppTab.allCases)
    }

    func testAnArrangedOrderIsAddedToRatherThanOverwritten() {
        let store = defaults("tabs.arranged.test")
        store.set(["settings", "servers", "metrics", "vpn", "configurator"], forKey: "tabs.order")
        let order = TabBarSettings(defaults: store).order
        XCTAssertEqual(order.first, .settings, "their arrangement survives")
        XCTAssertTrue(order.contains(.containers))
        XCTAssertEqual(order.count, AppTab.allCases.count)
    }

    // MARK: - Placement

    func testContainersStartInsideTheServerAndNotOnTheBar() {
        let placement = ContainersDisplaySettings.placement(from: "")
        XCTAssertEqual(placement, .server)
        XCTAssertFalse(placement.showsTab, "the tab is off until somebody turns it on")
        XCTAssertTrue(placement.showsInsideServer)
    }

    func testEitherPlaceOrBothCanBeChosen() {
        XCTAssertTrue(ContainersPlacement.section.showsTab)
        XCTAssertFalse(ContainersPlacement.section.showsInsideServer)
        XCTAssertTrue(ContainersPlacement.both.showsTab)
        XCTAssertTrue(ContainersPlacement.both.showsInsideServer)
    }

    /// Metrics keeps ITS default: both
    func testMetricsStillDefaultsToBoth() {
        XCTAssertEqual(MetricsDisplaySettings.placement(from: ""), .both)
    }

    // MARK: - Welcome

    /// Shown once
    func testTheWelcomeIsShownOnceAndThenNeverAgain() {
        let store = defaults("welcome.shown.test")
        WelcomeState.store = store
        defer { WelcomeState.store = .standard }

        WelcomeState.forget()
        XCTAssertFalse(WelcomeState.hasBeenShown)
        WelcomeState.markShown()
        XCTAssertTrue(WelcomeState.hasBeenShown)
        WelcomeState.forget()
    }
}
