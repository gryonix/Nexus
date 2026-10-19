import XCTest

@testable import gryonixNexus

@MainActor
final class GroupStripStyleTests: XCTestCase {
    private func store(_ name: String) -> UserDefaults {
        let store = UserDefaults(suiteName: name)!
        store.removePersistentDomain(forName: name)
        store.set(true, forKey: "welcome.shown")
        return store
    }

    func testAnUnwrittenKeyFollowsTheBottomBar() {
        let fresh = store("groups.default")
        XCTAssertEqual(TabBarSettings(defaults: fresh).groupStripStyle, .custom)

        fresh.set(BarStyle.system.rawValue, forKey: "tabs.barStyle")
        XCTAssertEqual(TabBarSettings(defaults: fresh).groupStripStyle, .system,
                       "an install that asked for Apple's bar must not keep this app's groups strip")
    }

    func testItsOwnChoiceOutlivesTheBottomBarsAndARestart() {
        let defaults = store("groups.persist")
        let first = TabBarSettings(defaults: defaults)
        first.groupStripStyle = .system
        first.barStyle = .custom

        let second = TabBarSettings(defaults: defaults)
        XCTAssertEqual(second.groupStripStyle, .system,
                       "the groups strip must keep its own answer once one is written")
        XCTAssertEqual(second.barStyle, .custom, "the two switches are separate")
    }

    func testAnUnrecognisedStoredValueFallsBackToTheBottomBar() {
        let defaults = store("groups.garbage")
        defaults.set("liquid-glass-deluxe", forKey: "fleet.groupsStyle")
        defaults.set(BarStyle.system.rawValue, forKey: "tabs.barStyle")
        XCTAssertEqual(TabBarSettings(defaults: defaults).groupStripStyle, .system)
    }
}
