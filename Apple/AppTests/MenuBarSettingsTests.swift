#if os(macOS)
import XCTest
@testable import gryonixNexus

@MainActor
final class MenuBarSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "MenuBarSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testTheMenuBarItemIsOnUntilSomebodyTurnsItOff() {
        XCTAssertTrue(MenuBarSettings(defaults: defaults).showsItem)
        XCTAssertFalse(MenuBarSettings(defaults: defaults).accessoryOnly)
    }

    func testTurningOffTheMenuBarItemAlsoGivesTheDockIconBack() {
        let settings = MenuBarSettings(defaults: defaults)
        settings.accessoryOnly = true

        settings.showsItem = false

        XCTAssertFalse(settings.accessoryOnly,
                       "no status item and no Dock icon is an app nothing can open")
    }

    func testBothSwitchesSurviveALaunch() {
        let first = MenuBarSettings(defaults: defaults)
        first.showsItem = true
        first.accessoryOnly = true

        let second = MenuBarSettings(defaults: defaults)

        XCTAssertTrue(second.showsItem)
        XCTAssertTrue(second.accessoryOnly)
    }

    func testTurningTheItemBackOnDoesNotBringBackTheHiddenDockIcon() {
        let settings = MenuBarSettings(defaults: defaults)
        settings.accessoryOnly = true
        settings.showsItem = false

        settings.showsItem = true

        XCTAssertFalse(settings.accessoryOnly,
                       "a setting that was cancelled must not come back on its own")
    }
}
#endif
