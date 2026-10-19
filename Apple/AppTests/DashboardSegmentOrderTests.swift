import XCTest

@testable import gryonixNexus

@MainActor
final class DashboardSegmentOrderTests: XCTestCase {
    private func defaults(_ name: String) -> UserDefaults {
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return store
    }

    /// Nobody has arranged anything yet: the catalog's own order
    func testTheDefaultOrderIsTheCatalogOrder() {
        XCTAssertEqual(DashboardTabSettings(defaults: defaults("segments.default.test")).order,
                       DashboardTab.allCases)
    }

    func testTheOrderIsAppliedToWhatTheServerOffers() {
        let store = defaults("segments.apply.test")
        store.set(["vpn", "general", "operations"], forKey: "dashboard.segmentOrder")
        let settings = DashboardTabSettings(defaults: store)
        settings.order = [.vpn, .general, .operations]

        XCTAssertEqual(settings.ordered([.general, .operations, .vpn]),
                       [.vpn, .general, .operations],
                       "the owner's order, not the enum's")
        XCTAssertEqual(settings.ordered([.general, .operations]),
                       [.general, .operations],
                       "a server without a VPN simply does not draw that one")
        XCTAssertEqual(settings.ordered([.general, .hosts, .vpn]),
                       [.vpn, .general, .hosts],
                       "a segment the stored order never named is still drawn, last")
    }

    func testAnAddedSegmentIsInsertedWhereItBelongs() {
        let stored: [DashboardTab] = [.vpn, .general, .operations]
        let reconciled = DashboardTabSettings.reconcile(stored: stored)
        XCTAssertEqual(reconciled.count, DashboardTab.allCases.count)
        XCTAssertEqual(Array(reconciled.prefix(1)), [.vpn], "their arrangement survives")
        XCTAssertEqual(reconciled, [.vpn, .terminal, .general, .operations, .hosts, .containers])
    }

    func testAnEmptyStoredOrderIsTheFullCatalog() {
        XCTAssertEqual(DashboardTabSettings.reconcile(stored: []), DashboardTab.allCases)
    }
    func testHidingASegmentAppliesToThatServerOnly() {
        let store = defaults("segments.perserver.test")
        let settings = DashboardTabSettings(defaults: store)
        let mine = UUID(), other = UUID()
        let available: [DashboardTab] = [.general, .operations, .hosts, .containers]

        settings.setVisible(false, for: .containers, on: mine, available: available)

        XCTAssertFalse(settings.ordered(available, on: mine).contains(.containers))
        XCTAssertTrue(settings.ordered(available, on: other).contains(.containers),
                      "another server keeps it")
        XCTAssertEqual(settings.ordered(available, on: other), settings.ordered(available),
                       "a server nobody arranged shows everything it has")
    }

    func testTheLastSegmentCannotBeTurnedOff() {
        let store = defaults("segments.last.test")
        let settings = DashboardTabSettings(defaults: store)
        let id = UUID()
        let available: [DashboardTab] = [.general, .operations]

        settings.setVisible(false, for: .operations, on: id, available: available)
        XCTAssertFalse(settings.canHide(.general, on: id, available: available))
        settings.setVisible(false, for: .general, on: id, available: available)
        XCTAssertEqual(settings.ordered(available, on: id), [.general],
                       "the refusal holds — the last one stays")
    }

    /// It survives a relaunch, like every other arrangement here
    func testTheSwitchesArePersisted() {
        let name = "segments.persist.test"
        let store = defaults(name)
        let id = UUID()
        let available: [DashboardTab] = [.general, .operations, .vpn]
        DashboardTabSettings(defaults: store).setVisible(false, for: .vpn, on: id, available: available)

        let reopened = DashboardTabSettings(defaults: UserDefaults(suiteName: name)!)
        XCTAssertFalse(reopened.isVisible(.vpn, on: id))
        XCTAssertTrue(reopened.isVisible(.general, on: id))
    }
}
