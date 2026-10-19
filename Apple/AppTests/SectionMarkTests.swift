import ServiceCatalog
import SwiftUI
import XCTest

@testable import gryonixNexus

final class SectionMarkTests: XCTestCase {
    /// BOTH of them
    private var vpnSources: [URL] {
        let apple = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AppTests
            .deletingLastPathComponent()   // Apple
        return ["App/Features/VPN", "App/Features/Dashboard/VPN"]
            .map(apple.appendingPathComponent)
    }

    private var markContents: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Shared/BrandMarks.xcassets/TabIconLogo.imageset/Contents.json")
    }

    func testTheVPNScreensDrawTheMarkAndNeverTheSymbol() throws {
        let files = try vpnSources.flatMap { try swiftFiles(in: $0) }
        XCTAssertGreaterThan(files.count, 4, "the source sweep found almost nothing — check the paths")

        var offenders: [String] = []
        for file in files {
            let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Prose about the rule is not a use of it.
                if trimmed.hasPrefix("//") { continue }
                if line.contains("\"lock.shield\"") {
                    offenders.append("\(file.lastPathComponent):\(index + 1)  \(trimmed)")
                }
            }
        }

        XCTAssertEqual(offenders, [], """
            These draw the VPN section with a stock symbol while the tab bar \
            beside them draws the owner's mark. Ask `AppTab.vpn.icon`:
            \(offenders.joined(separator: "\n"))
            """)
    }

    /// The other half
    func testTheSectionAsksAppTabForItsPicture() throws {
        let files = try vpnSources.flatMap { try swiftFiles(in: $0) }
        let uses = try files.reduce(0) { total, file in
            let source = try String(contentsOf: file, encoding: .utf8)
            return total + source.components(separatedBy: "AppTab.vpn.icon").count - 1
        }
        XCTAssertGreaterThan(uses, 0, "no VPN screen asks AppTab for the section's picture")
    }

    func testTheMarkKeepsItsVectorDataAndTemplateRendering() throws {
        let data = try Data(contentsOf: markContents)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try XCTUnwrap(json["properties"] as? [String: Any],
                                       "the imageset declares no properties at all")
        XCTAssertEqual(properties["preserves-vector-representation"] as? Bool, true)
        XCTAssertEqual(properties["template-rendering-intent"] as? String, "template")
    }

    // MARK: - The mark that tracks the tunnel

    func testTheVPNMarkClosesAroundTheGlobeOnlyWhileTheTunnelIsUp() {
        XCTAssertEqual(AppTab.vpn.icon(tunnelActive: true), Image("TabIconLogo"))
        XCTAssertEqual(AppTab.vpn.icon(tunnelActive: false), Image("TabIconGlobe"))
        XCTAssertNotEqual(AppTab.vpn.icon(tunnelActive: true),
                          AppTab.vpn.icon(tunnelActive: false),
                          "one picture for both states says nothing")
    }

    func testTheStillFormIsAlwaysTheMark() {
        XCTAssertEqual(AppTab.vpn.icon, Image("TabIconLogo"))
    }

    /// Every other section ignores the tunnel
    func testNoOtherSectionChangesPictureWithTheTunnel() {
        for tab in AppTab.allCases where tab != .vpn {
            XCTAssertEqual(tab.icon(tunnelActive: true), tab.icon,
                           "\(tab.rawValue) answers a second picture")
            XCTAssertEqual(tab.icon(tunnelActive: false), tab.icon,
                           "\(tab.rawValue) answers a second picture")
        }
    }

    func testTheBarDrawsEverySectionOutlined() {
        for tab in AppTab.allCases {
            XCTAssertNotNil(tab.barIcon(tunnelActive: false))
            XCTAssertNotNil(tab.barIcon(tunnelActive: true))
        }
    }

    func testTheShellDrawsTheBarFromTheLiveTunnel() throws {
        let shell = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("App/Navigation/RootTabView.swift")
        let source = try String(contentsOf: shell, encoding: .utf8)
        XCTAssertTrue(source.contains("TunnelController.shared"),
                      "the shell no longer observes the tunnel it draws")
        let calls = source.components(separatedBy: "barIcon(").count - 1
        XCTAssertGreaterThan(calls, 2, "the bar call sites went missing")
        XCTAssertEqual(source.components(separatedBy: "barIcon(tunnelActive:").count - 1, calls,
                       "a bar call site draws the section's picture without the tunnel")
    }

    func testTheGlobeKeepsItsVectorDataAndTemplateRendering() throws {
        let contents = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Shared/BrandMarks.xcassets/TabIconGlobe.imageset/Contents.json")
        let data = try Data(contentsOf: contents)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try XCTUnwrap(json["properties"] as? [String: Any],
                                       "the imageset declares no properties at all")
        XCTAssertEqual(properties["preserves-vector-representation"] as? Bool, true)
        XCTAssertEqual(properties["template-rendering-intent"] as? String, "template")
    }

    // MARK: - The rest of the app

    func testNothingDrawsTheTunnelsStateAsABareSymbol() throws {
        let apple = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let files = try ["App", "Widgets"]
            .map(apple.appendingPathComponent)
            .flatMap { try swiftFiles(in: $0) }
        var offenders: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            if source.contains("Image(systemName: TunnelPresentation.symbol(") {
                offenders.append(file.lastPathComponent)
            }
        }
        XCTAssertEqual(offenders, [], """
            These draw the tunnel's state with a stock symbol. Ask
            `TunnelPresentation.mark(_:size:)`, which answers the brand mark
            while the tunnel is up: \(offenders.joined(separator: ", "))
            """)
    }

    func testTheVPNShelfDrawsTheMarkAndNoOtherShelfDoes() {
        XCTAssertTrue(ServiceCategory.vpn.drawsBrandMark)
        XCTAssertFalse(ServiceCategory.secrets.drawsBrandMark,
                       "the secrets shelf answers the same symbol name and is not the VPN")
        for category in ServiceCategory.selectable where category.id != ServiceCategory.vpn.id {
            XCTAssertFalse(category.drawsBrandMark, "\(category.id) is not the VPN shelf")
        }
    }

    func testTheWidgetExtensionCarriesTheMarks() throws {
        let apple = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(contentsOf: apple.appendingPathComponent("project.yml"),
                                 encoding: .utf8)
        let mentions = project.components(separatedBy: "Shared/BrandMarks.xcassets").count - 1
        XCTAssertGreaterThanOrEqual(mentions, 2,
                                    "the marks are listed for fewer than two targets")
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory,
                                                          includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
