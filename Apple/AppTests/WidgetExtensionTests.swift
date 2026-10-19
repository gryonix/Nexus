import VPNTunnel
import XCTest
@testable import gryonixNexus

final class WidgetExtensionTests: XCTestCase {
    private var appleRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AppTests
            .deletingLastPathComponent()  // Apple
    }

    private func read(_ relative: String) throws -> String {
        try String(contentsOf: appleRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    // MARK: - The extension is a target, and the app carries it

    func testTheWidgetExtensionIsARealTarget() throws {
        let manifest = try read("project.yml")
        XCTAssertTrue(manifest.contains("gryonixNexusWidgets:"),
                      "no widget target in project.yml")
        XCTAssertTrue(manifest.contains("type: app-extension"),
                      "the widget target is not an app extension")
        XCTAssertTrue(manifest.contains("- Widgets/Extension"),
                      "the widget target does not compile Widgets/Extension")
    }

    func testTheAppEmbedsTheWidgetExtension() throws {
        let manifest = try read("project.yml")
        XCTAssertTrue(manifest.contains("- target: gryonixNexusWidgets"),
                      "the app does not depend on the widget extension, so nothing embeds it")

        let pbxproj = try read("gryonixNexus.xcodeproj/project.pbxproj")
        XCTAssertTrue(pbxproj.contains("gryonixNexusWidgets.appex"),
                      "the generated project has no widget extension product — run `xcodegen generate`")
        XCTAssertTrue(pbxproj.contains("Embed Foundation Extensions")
                        || pbxproj.contains("Embed App Extensions")
                        || pbxproj.contains("Embed PlugIns"),
                      "the app has no phase that embeds an extension")
    }

    // MARK: - Every widget written is a widget registered

    private func declaredWidgets() throws -> Set<String> {
        let directory = appleRoot.appendingPathComponent("Widgets/Extension")
        let files = try FileManager.default.contentsOfDirectory(at: directory,
                                                                includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "no widget sources were read at all")

        var names: Set<String> = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for pattern in [#"struct (\w+): Widget\b"#, #"struct (\w+): ControlWidget\b"#] {
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(text.startIndex..., in: text)
                for match in regex.matches(in: text, range: range) {
                    if let r = Range(match.range(at: 1), in: text) { names.insert(String(text[r])) }
                }
            }
        }
        return names
    }

    func testEveryWidgetIsRegisteredInTheBundle() throws {
        let declared = try declaredWidgets()
        XCTAssertTrue(declared.contains("VPNStatusWidget"), "the widget scan found nothing it should")

        let bundle = try read("Widgets/Extension/gryonixNexusWidgetBundle.swift")
        for widget in declared {
            XCTAssertTrue(bundle.contains("\(widget)()"),
                          "\(widget) is written but never added to the widget bundle — it ships as dead code")
        }
    }

    func testTheBundleHasExactlyOneEntryPoint() throws {
        let bundle = try read("Widgets/Extension/gryonixNexusWidgetBundle.swift")
        XCTAssertTrue(bundle.contains("@main"), "the extension has no entry point")

        let directory = appleRoot.appendingPathComponent("Widgets/Extension")
        let mains = try FileManager.default.contentsOfDirectory(at: directory,
                                                                includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .filter { (try? String(contentsOf: $0, encoding: .utf8))?.contains("@main") == true }
        XCTAssertEqual(mains.count, 1, "exactly one file may declare the extension's entry point")
    }

    // MARK: - What this build can and cannot do, said out loud

    func testTheUnsharedContainerIsReportedRatherThanHidden() throws {
        let container = try read("Packages/gryonixNexus/Sources/VPNTunnel/SharedContainer.swift")
        let view = try read("Widgets/Shared/VPNStatusWidgetView.swift")

        XCTAssertTrue(container.contains("appGroupIdentifier"),
                      "SharedContainer.swift was not read")
        XCTAssertTrue(view.contains("entry.available"),
                      "the widget draws without ever asking whether it read anything")

        if container.contains("appGroupIdentifier: String? = nil") {
            XCTAssertFalse(SharedContainer.isShared,
                           "no App Group is declared, so nothing may claim the container is shared")
        }
    }

    func testTheMacGroupIsPrefixedByTheTeam() throws {
        for path in ["gryonixNexus-macOS.entitlements",
                     "Widgets/Extension/gryonixNexusWidgets-macOS.entitlements",
                     "TunnelExtension/gryonixNexusTunnel-macOS.entitlements"] {
            XCTAssertTrue(try read(path).contains("<string>Z4PMRLY8L2.group.com.skaymer.gryonixnexus</string>"),
                          "\(path) must name the group with the team prefix")
        }
    }

    func testEveryTargetThatReadsTheContainerCarriesTheGroup() throws {
        let group = try XCTUnwrap(SharedContainer.appGroupIdentifier)
        for path in ["gryonixNexus.entitlements", "gryonixNexus-macOS.entitlements",
                     "Widgets/Extension/gryonixNexusWidgets.entitlements",
                     "Widgets/Extension/gryonixNexusWidgets-macOS.entitlements",
                     "TunnelExtension/gryonixNexusTunnel.entitlements",
                     "TunnelExtension/gryonixNexusTunnel-macOS.entitlements"] {
            XCTAssertTrue(try read(path).contains(group), "\(path) lacks the App Group")
        }
    }
}
