import XCTest

@testable import gryonixNexus

@MainActor
final class SystemStripMenuTests: XCTestCase {
    private func source(_ path: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppTests
            .deletingLastPathComponent()   // Apple
            .appendingPathComponent(path), encoding: .utf8)
    }

    func testTheSystemSectionStripGetsPerSegmentMenus() throws {
        let text = try source("App/Features/Dashboard/DashboardView.swift")
        XCTAssertTrue(text.contains(".segmentMenus(count: visibleTabs.count, probe: \"sections\")"),
                      "the system section strip has no hold menu again — holding a segment "
                      + "there does nothing at all, which is the defect this pins")
        XCTAssertTrue(text.contains("return segmentMenu(for: visibleTabs[index])"),
                      "the system strip builds its own menu instead of the one this app's "
                      + "strip uses — two menus for one gesture is how they start disagreeing")
    }

    /// The fleet's group strip, same rule
    func testTheSystemGroupStripGetsPerSegmentMenus() throws {
        let text = try source("App/Features/Servers/ServerListView.swift")
        XCTAssertTrue(text.contains(".segmentMenus(count: tagSegments.count, probe: \"groups\")"),
                      "the system group strip has no per-segment hold menu")
    }

    func testTheGroupStripNoLongerMenusTheWholeControl() throws {
        let text = try source("App/Features/Servers/ServerListView.swift")
        XCTAssertFalse(text.contains(".contextMenu { selectedGroupActions }"),
                       "the whole-control menu is back beside the per-segment one: a held "
                       + "segment and the chosen segment would answer the same hold differently")
    }

    func testAScreenshotRunCanForceTheSystemStyle() throws {
        let text = try source("App/Services/TabBarSettings.swift")
        XCTAssertTrue(text.contains("GRYONIXNEXUS_DEMO_BAR_STYLE"),
                      "nothing can put a fresh simulator on the system strips any more, "
                      + "so nothing can photograph their hold menus")
    }

    func testTheForcedStyleIsNotPersisted() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        defaults.set(true, forKey: "welcome.shown")
        _ = TabBarSettings(defaults: defaults)
        XCTAssertNil(defaults.string(forKey: "tabs.barStyle"),
                     "building the settings wrote a bar style nobody chose")
        XCTAssertNil(defaults.string(forKey: "dashboard.stripStyle"))
        XCTAssertNil(defaults.string(forKey: "fleet.groupsStyle"))
    }
}
