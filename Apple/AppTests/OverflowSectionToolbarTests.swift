import XCTest

@testable import gryonixNexus

final class OverflowSectionToolbarTests: XCTestCase {
    /// Which file is the root of which section
    private static let roots: [(tab: AppTab, file: String)] = [
        (.servers, "App/Features/Servers/ServerListView.swift"),
        (.containers, "App/Features/Containers/ContainersFleetView.swift"),
        (.metrics, "App/Features/Metrics/MetricsDashboardView.swift"),
        (.vpn, "App/Features/VPN/VPNSectionView.swift"),
        (.terminal, "App/Features/Terminal/TerminalSection.swift"),
        (.configurator, "App/Navigation/AppRootView.swift"),
        (.settings, "App/Features/Settings/AppSettingsView.swift")
    ]

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppTests
            .deletingLastPathComponent()   // repo root
    }

    func testEverySectionRootCarriesTheOverflowToolbar() throws {
        XCTAssertEqual(Set(Self.roots.map(\.tab)), Set(AppTab.allCases),
                       "a section exists that this list does not name")
        for (tab, path) in Self.roots {
            let source = try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue((source.contains(".sectionToolbar(.\(tab.rawValue))")
                           || source.contains(".sectionToolbar(.\(tab.rawValue),")
                           || source.contains(".sectionToolbar(.\(tab.rawValue)) {")),
                          "\(path) is the root of the \(tab.rawValue) section and does not carry "
                          + "`.sectionToolbar(.\(tab.rawValue))` — opened from More it would "
                          + "have no way back")
        }
    }

    func testTheToolbarIsAppliedInsideTheNavigationStack() throws {
        for (tab, path) in Self.roots {
            let source = try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
            let lines = source.components(separatedBy: .newlines)
            guard let call = lines.firstIndex(where: { $0.contains(".sectionToolbar(") }),
                  let stack = lines.firstIndex(where: { $0.contains("NavigationStack") }) else {
                XCTFail("\(path): expected both a NavigationStack and the toolbar call")
                continue
            }
            XCTAssertGreaterThan(call, stack, "\(path): the call must come after the stack opens")

            let owner = Self.declaration(containing: call, in: lines)
            let host = Self.declaration(containing: stack, in: lines)
            if owner == host {
                let indent = { (line: String) in line.prefix { $0 == " " }.count }
                XCTAssertGreaterThan(indent(lines[call]), indent(lines[stack]),
                                     "\(path): `.sectionToolbar(.\(tab.rawValue))` sits at the "
                                     + "stack's own level, so it lands outside it and draws nothing")
            } else {
                XCTAssertTrue(Self.reachable(owner, from: host, in: source),
                              "\(path): `.sectionToolbar(.\(tab.rawValue))` lives in `\(owner)`, "
                              + "which nothing inside the NavigationStack names — so it lands "
                              + "outside the stack and draws nothing")
            }
        }
    }

    private static func declaration(containing line: Int, in lines: [String]) -> String {
        for index in stride(from: line, through: 0, by: -1) {
            let text = lines[index]
            for keyword in ["var ", "func "] where text.contains(keyword) {
                guard let start = text.range(of: keyword) else { continue }
                let rest = text[start.upperBound...]
                let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                if !name.isEmpty { return String(name) }
            }
        }
        return ""
    }

    private static func reachable(_ name: String, from: String, in source: String,
                                  depth: Int = 4) -> Bool {
        guard depth > 0, !name.isEmpty, !from.isEmpty else { return false }
        guard let body = body(of: from, in: source) else { return false }
        if body.contains(name) { return true }
        // Anything else the host names, followed one step further.
        for candidate in declarations(in: source) where body.contains(candidate) {
            if candidate != from, reachable(name, from: candidate, in: source, depth: depth - 1) {
                return true
            }
        }
        return false
    }

    /// Every `var`/`func` name declared in a file
    private static func declarations(in source: String) -> [String] {
        source.components(separatedBy: .newlines).compactMap { line in
            for keyword in ["var ", "func "] where line.contains(keyword) {
                guard let start = line.range(of: keyword) else { continue }
                let name = line[start.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                if !name.isEmpty { return String(name) }
            }
            return nil
        }
    }

    private static func body(of name: String, in source: String) -> String? {
        let lines = source.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: {
            $0.contains("var \(name)") || $0.contains("func \(name)")
        }) else { return nil }
        var end = lines.count
        for index in (start + 1)..<lines.count where
            lines[index].contains("var ") || lines[index].contains("func ") {
            end = index
            break
        }
        return lines[start..<end].joined(separator: "\n")
    }
}
