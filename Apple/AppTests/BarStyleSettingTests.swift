import XCTest

@testable import gryonixNexus

@MainActor
final class BarStyleSettingTests: XCTestCase {
    private func settings(_ name: String) -> (TabBarSettings, UserDefaults) {
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        return (TabBarSettings(defaults: store), store)
    }

    func testAFreshInstallStartsOnAppleBarsEverywhere() {
        let (tabs, store) = settings("bar.fresh")
        XCTAssertEqual(tabs.barStyle, .system)
        XCTAssertEqual(tabs.sectionStripStyle, .system)
        XCTAssertEqual(tabs.groupStripStyle, .system)
        XCTAssertEqual(store.string(forKey: "tabs.barStyle"), "system", "the start must be written down")
    }

    func testAnExistingInstallWithAnUnwrittenKeyKeepsThisAppsOwnBar() {
        let name = "bar.default"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        store.set(true, forKey: "welcome.shown")
        XCTAssertEqual(TabBarSettings(defaults: store).barStyle, .custom)
    }

    func testAChoiceOfSystemSurvivesARestart() {
        let name = "bar.persist"
        let (first, store) = settings(name)
        first.barStyle = .system

        let second = TabBarSettings(defaults: store)
        XCTAssertEqual(second.barStyle, .system,
                       "the setting must round-trip — a picked system bar cannot revert to custom")
    }

    func testAnUnrecognisedStoredValueFallsBackToCustom() {
        let name = "bar.garbage"
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        store.set("liquid-glass-deluxe", forKey: "tabs.barStyle")
        XCTAssertEqual(TabBarSettings(defaults: store).barStyle, .custom)
    }
}
