import XCTest

@testable import gryonixNexus

@MainActor
final class ShellSectionVisibilityTests: XCTestCase {
    private var defaults: UserDefaults!
    private var settings: TabBarSettings!
    private let suite = "ShellSectionVisibilityTests"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
        settings = TabBarSettings(defaults: defaults)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        defaults = nil
        settings = nil
        super.tearDown()
    }

    /// A plain section: nothing but the layout switch decides it
    func testAPlainSectionFollowsTheLayoutSwitch() {
        XCTAssertTrue(ShellSectionVisibility.isOnBar(.configurator, tabs: settings, defaults: defaults))
        ShellSectionVisibility.setOnBar(false, for: .configurator, tabs: settings, defaults: defaults)
        XCTAssertFalse(settings.isVisible(.configurator))
        XCTAssertFalse(ShellSectionVisibility.isOnBar(.configurator, tabs: settings, defaults: defaults))
        ShellSectionVisibility.setOnBar(true, for: .configurator, tabs: settings, defaults: defaults)
        XCTAssertTrue(ShellSectionVisibility.isOnBar(.configurator, tabs: settings, defaults: defaults))
    }

    func testTheTerminalIsOffTheBarWhileNothingIsHidden() {
        XCTAssertTrue(settings.isVisible(.terminal), "the fixture stopped testing the placement gate")
        XCTAssertFalse(ShellSectionVisibility.isOnBar(.terminal, tabs: settings, defaults: defaults))
    }

    func testSwitchingOnAPlacedSectionMovesThePlacement() {
        ShellSectionVisibility.setOnBar(true, for: .terminal, tabs: settings, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: TerminalDisplaySettings.placementKey),
                       TerminalPlacement.both.rawValue)
        XCTAssertTrue(ShellSectionVisibility.isOnBar(.terminal, tabs: settings, defaults: defaults))
    }

    func testSwitchingOffAPlacedSectionKeepsItInsideTheServer() {
        ShellSectionVisibility.setOnBar(true, for: .containers, tabs: settings, defaults: defaults)
        XCTAssertTrue(ShellSectionVisibility.isOnBar(.containers, tabs: settings, defaults: defaults))

        ShellSectionVisibility.setOnBar(false, for: .containers, tabs: settings, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: ContainersDisplaySettings.placementKey),
                       ContainersPlacement.server.rawValue)
        XCTAssertFalse(ShellSectionVisibility.isOnBar(.containers, tabs: settings, defaults: defaults))
        XCTAssertTrue(settings.isVisible(.containers),
                      "the section was hidden outright instead of moved inside the server")
    }

    func testMetricsUsesItsOwnPlacementSpelling() {
        ShellSectionVisibility.setOnBar(false, for: .metrics, tabs: settings, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: MetricsDisplaySettings.placementKey),
                       MetricsPlacement.server.rawValue)
        XCTAssertFalse(ShellSectionVisibility.isOnBar(.metrics, tabs: settings, defaults: defaults))
    }

    func testSettingsCannotBeTakenOffTheBar() {
        ShellSectionVisibility.setOnBar(false, for: .settings, tabs: settings, defaults: defaults)
        XCTAssertTrue(ShellSectionVisibility.isOnBar(.settings, tabs: settings, defaults: defaults))
    }
}
