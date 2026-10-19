import XCTest

@testable import gryonixNexus

final class DashboardSwitcherTests: XCTestCase {
    private var dashboardSource: String {
        get throws {
            let repoRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // AppTests
                .deletingLastPathComponent()   // repo root
            return try String(contentsOf: repoRoot
                .appendingPathComponent("App/Features/Dashboard/DashboardView.swift"),
                              encoding: .utf8)
        }
    }

    func testTheSwitcherIsTheSystemSegmentedPicker() throws {
        let body = try switcherBody()
        XCTAssertTrue(body.contains("Picker(\"View\", selection: $tab)"),
                      "the switcher must be a plain SwiftUI Picker")
        XCTAssertTrue(body.contains(".pickerStyle(.segmented)"),
                      "the switcher must use the system segmented style")
    }

    func testNothingRestylesTheSwitcher() throws {
        let body = try switcherBody()
        for banned in ["glassEffect", "matchedGeometryEffect", "Capsule(", "RoundedRectangle(",
                       ".background", ".overlay", ".tint(", ".buttonStyle(", ".font(",
                       ".foregroundStyle(", ".pickerStyle(.palette)"] {
            XCTAssertFalse(body.contains(banned),
                           "`\(banned)` restyles the switcher — this bar is the system control as "
                           + "the system draws it, and the owner asked for that to stay (2026-08-23)")
        }
    }

    /// The macOS half: in the title bar, and nowhere else
    func testOnMacTheSwitcherSitsInTheTitleBar() throws {
        let source = try dashboardSource
        guard let mark = source.range(of: "ToolbarItem(placement: .principal)") else {
            return XCTFail("the macOS switcher must be a principal toolbar item — in the content "
                           + "AppKit draws the old bordered control with a blue-filled segment")
        }
        let item = source[mark.lowerBound...].prefix(200)
        XCTAssertTrue(item.contains("tabPicker"),
                      "the principal toolbar item must hold the switcher itself")
        let mac = try macBranchOfContent()
        XCTAssertFalse(mac.contains("tabPicker"),
                       "the macOS content must NOT draw the switcher as well — it belongs in the "
                       + "title bar, and a second copy above the list is the bordered control again")
    }

    func testNoHandDrawnSegmentedControlExistsInTheApp() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let app = repoRoot.appendingPathComponent("App")
        let files = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty, "the sweep found no sources — it would pass on nothing")
        let allowed: Set<String> = ["DashboardView.swift", "DashboardTabOrderView.swift",
                                    "DashboardSegmentStrip.swift"]
        var checked = 0
        for file in files where !allowed.contains(file.lastPathComponent) {
            let source = try String(contentsOf: file, encoding: .utf8)
            checked += 1
            for line in source.components(separatedBy: .newlines) {
                let ownsSelection = line.contains("DashboardTab")
                    && (line.contains("@Binding") || line.contains("@State"))
                XCTAssertFalse(ownsSelection,
                               "\(file.lastPathComponent) owns the section selection "
                               + "(\(line.trimmingCharacters(in: .whitespaces))) — a second view "
                               + "driving the strip is a hand-drawn switcher, and beside the real "
                               + "control a drawn copy reads as an imitation of it")
            }
        }
        XCTAssertGreaterThan(checked, 50, "the sweep barely looked at anything")
    }

    func testOniOSTheSwitcherIsTheStripAboveTheList() throws {
        let content = try iOSBranchOfContent()
        XCTAssertTrue(content.contains("DashboardSegmentStrip("),
                      "the iOS content must hold the strip — the system control truncates six "
                      + "sections to \"Contain…\" and \"Termin…\", which is what it replaced")
        XCTAssertFalse(content.contains("tabPicker"),
                       "the iOS content must NOT draw the segmented picker as well — two "
                       + "switchers over one list is the round this file exists to stop")
    }

    func testTheStripExists() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let strip = repoRoot
            .appendingPathComponent("App/Features/Dashboard/DashboardSegmentStrip.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: strip.path),
                      "the iOS switcher is gone — if that is deliberate, this file's header is "
                      + "the place to say what replaced it")
    }

    // MARK: - Slicing the source

    private func switcherBody() throws -> String {
        let source = try dashboardSource
        guard let start = source.range(of: "private var tabPicker: some View {") else {
            throw XCTSkip("the switcher is no longer called `tabPicker`")
        }
        guard let end = source.range(of: "\n    }\n", range: start.upperBound..<source.endIndex) else {
            return String(source[start.upperBound...])
        }
        return String(source[start.upperBound..<end.lowerBound])
    }

    private func iOSBranchOfContent() throws -> String {
        let source = try dashboardSource
        guard let body = source.range(of: "private var content: some View {"),
              let start = source.range(of: "#else", range: body.upperBound..<source.endIndex),
              let end = source.range(of: "#endif", range: start.upperBound..<source.endIndex) else {
            return ""
        }
        return String(source[start.upperBound..<end.lowerBound])
    }

    /// The `#if os(macOS)` branch of `content`
    private func macBranchOfContent() throws -> String {
        let source = try dashboardSource
        guard let body = source.range(of: "private var content: some View {"),
              let start = source.range(of: "#if os(macOS)", range: body.upperBound..<source.endIndex),
              let end = source.range(of: "#else", range: start.upperBound..<source.endIndex) else {
            return ""
        }
        return String(source[start.upperBound..<end.lowerBound])
    }
}
