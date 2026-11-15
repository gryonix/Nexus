import XCTest

@testable import ServerControlSSH

/// The path choice decides which links are tried
final class HomePathChoiceTests: XCTestCase {
    private func suite() -> UserDefaults {
        let name = "home-path-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testAutomaticTriesEverything() {
        XCTAssertEqual(HomePathChoice.automatic.plan, .init(localFirst: true, usesVPS: true, localLastResort: true))
    }

    func testThroughVPSNeverTouchesTheLocalNetwork() {
        let plan = HomePathChoice.throughVPS.plan
        XCTAssertFalse(plan.localFirst)
        XCTAssertFalse(plan.localLastResort)
        XCTAssertTrue(plan.usesVPS)
    }

    func testLocalNetworkNeverUsesTheVPS() {
        let plan = HomePathChoice.localNetwork.plan
        XCTAssertTrue(plan.localFirst)
        XCTAssertFalse(plan.usesVPS)
    }

    func testChoiceIsStoredPerServerAndDefaultsToAutomatic() {
        let defaults = suite()
        let first = UUID(), second = UUID()
        XCTAssertEqual(HomePathChoice.load(for: first, defaults: defaults), .automatic)
        HomePathChoice.save(.localNetwork, for: first, defaults: defaults)
        XCTAssertEqual(HomePathChoice.load(for: first, defaults: defaults), .localNetwork)
        XCTAssertEqual(HomePathChoice.load(for: second, defaults: defaults), .automatic)
        HomePathChoice.save(.automatic, for: first, defaults: defaults)
        XCTAssertNil(defaults.string(forKey: "home-path-" + first.uuidString))
    }
}
