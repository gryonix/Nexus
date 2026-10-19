import XCTest
@testable import gryonixNexus

/// The license list against the packages this app actually links
final class AboutTests: XCTestCase {
    private var appleRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // AppTests
            .deletingLastPathComponent()  // Apple
    }

    /// Package directory names from the package's own resolved pins
    private func resolvedPackageNames() throws -> Set<String> {
        let url = appleRoot.appendingPathComponent("Packages/gryonixNexus/Package.resolved")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let pins = (json?["pins"] as? [[String: Any]])
            ?? ((json?["object"] as? [String: Any])?["pins"] as? [[String: Any]])
            ?? []
        XCTAssertFalse(pins.isEmpty, "Package.resolved was read and understood as nothing")
        return Set(pins.compactMap { pin in
            let location = (pin["location"] as? String) ?? (pin["repositoryURL"] as? String)
            guard let location else { return nil }
            return URL(string: location)?.deletingPathExtension().lastPathComponent
        })
    }

    private func projectFilePackageNames() throws -> Set<String> {
        let url = appleRoot.appendingPathComponent("project.yml")
        let text = try String(contentsOf: url, encoding: .utf8)
        var names: Set<String> = []
        var inPackages = false
        var current: String?
        for line in text.components(separatedBy: .newlines) {
            if line == "packages:" { inPackages = true; continue }
            // Any other column-zero key ends the block.
            if inPackages, !line.hasPrefix(" "), !line.isEmpty { break }
            guard inPackages else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }
            // Exactly two spaces of indent is a package name.
            if line.hasPrefix("  "), !line.hasPrefix("   "), trimmed.hasSuffix(":") {
                current = String(trimmed.dropLast())
                continue
            }
            if trimmed.hasPrefix("url:"), let name = current { names.insert(name) }
        }
        return names
    }

    func testTheProjectFileIsReadAtAllAndNamesTheTwoItAloneDeclares() throws {
        let declared = try projectFilePackageNames()
        XCTAssertTrue(declared.contains("SwiftTerm"),
                      "project.yml was not parsed: SwiftTerm not found")
        XCTAssertTrue(declared.contains("Sparkle"),
                      "project.yml was not parsed: Sparkle not found")
        XCTAssertFalse(declared.contains("gryonixNexusPackage"),
                       "a path: package is our own source and needs no third-party notice")
    }

    func testEveryLinkedPackageHasALicenseInTheList() throws {
        let listed = Set(OpenSourceLicense.all.filter { $0.source == .package }.map(\.id))
        let resolved = try resolvedPackageNames().union(projectFilePackageNames())
        let linked = resolved.subtracting(OpenSourceLicense.notLinked)

        XCTAssertFalse(resolved.isEmpty, "neither dependency source was read")
        XCTAssertEqual(linked.subtracting(listed), [],
                       "a package the app links has no entry in the About screen")
        XCTAssertEqual(listed.subtracting(linked), [],
                       "the About screen lists a package the app no longer links")
    }

    func testTheNotLinkedExclusionIsTrueOfThisBuild() throws {
        let pbxproj = try String(
            contentsOf: appleRoot.appendingPathComponent("gryonixNexus.xcodeproj/project.pbxproj"),
            encoding: .utf8)
        let manifest = try String(
            contentsOf: appleRoot.appendingPathComponent("Packages/gryonixNexus/Package.swift"),
            encoding: .utf8)

        XCTAssertTrue(pbxproj.contains("SwiftTerm"), "project.pbxproj was not read")
        XCTAssertTrue(manifest.contains("Citadel"), "Package.swift was not read")

        for excluded in OpenSourceLicense.notLinked {
            let module = excluded
                .replacingOccurrences(of: "swift-", with: "")
                .split(separator: "-").map { $0.capitalized }.joined()
            for spelling in [excluded, module] {
                XCTAssertFalse(pbxproj.contains(spelling),
                               "\(excluded) is excluded as not linked, but \(spelling) appears in project.pbxproj")
                XCTAssertFalse(manifest.contains(spelling),
                               "\(excluded) is excluded as not linked, but \(spelling) appears in Package.swift")
            }
        }
    }

    func testEveryLicenseTextIsInTheBuild() throws {
        for license in OpenSourceLicense.all {
            let text = license.text(in: Bundle(for: Self.self)) ?? license.text()
            XCTAssertNotNil(text, "\(license.name): the license resource is missing from the bundle")
            XCTAssertFalse((text ?? "").isEmpty, "\(license.name): the license resource is empty")
        }
    }

    /// MIT asks for the copyright line, Apache-2.0 for its notice
    func testEachLicenseTextIsTheOneItClaimsToBe() throws {
        for license in OpenSourceLicense.all {
            let text = (license.text(in: Bundle(for: Self.self)) ?? license.text()) ?? ""
            switch license.terms {
            case "MIT":
                XCTAssertTrue(text.contains("MIT License") || text.contains("Permission is hereby granted"),
                              "\(license.name) is listed as MIT and its text is not")
            case "MPL-2.0":
                XCTAssertTrue(text.contains("Mozilla Public License"),
                              "\(license.name) is listed as MPL-2.0 and its text is not")
            case "AGPL-3.0":
                XCTAssertTrue(text.contains("GNU AFFERO GENERAL PUBLIC LICENSE"),
                              "\(license.name) is listed as AGPL-3.0 and its text is not")
            case "Various":
                XCTAssertTrue(text.hasPrefix("Third-party notices"),
                              "\(license.name) is listed as generated notices and its text is not")
            case "Apache-2.0":
                XCTAssertTrue(text.contains("Apache License"),
                              "\(license.name) is listed as Apache-2.0 and its text is not")
            default:
                XCTFail("\(license.name): unrecognised license \(license.terms)")
            }
        }
    }

    func testTheMacOnlyFlagMatchesTheFilterInTheProjectFile() throws {
        let text = try String(contentsOf: appleRoot.appendingPathComponent("project.yml"),
                              encoding: .utf8)
        for license in OpenSourceLicense.all {
            let filtered = text.contains("- package: \(license.id)")
                && text.range(of: "- package: \(license.id)[\\s\\S]{0,200}?destinationFilters: \\[macOS\\]",
                              options: .regularExpression) != nil
            XCTAssertEqual(license.isMacOnly, filtered,
                           "\(license.name): isMacOnly says \(license.isMacOnly), project.yml says \(filtered)")
        }
        #if os(macOS)
        XCTAssertEqual(OpenSourceLicense.shipped.count, OpenSourceLicense.all.count)
        #else
        XCTAssertFalse(OpenSourceLicense.shipped.contains { $0.id == "Sparkle" },
                       "the iOS build does not link Sparkle and must not claim its notice")
        XCTAssertEqual(OpenSourceLicense.shipped.count, OpenSourceLicense.all.count - 1)
        #endif
    }

    func testTheVersionComesFromTheBundleRatherThanFromAConstant() {
        XCTAssertNotEqual(AppRelease.version, "—")
        XCTAssertNotEqual(AppRelease.build, "—")
    }

    func testTheLinksAreAddressesRatherThanText() {
        XCTAssertEqual(AppRelease.sourceRepository.scheme, "https")
        XCTAssertEqual(AppRelease.securityPolicy.scheme, "https")
        XCTAssertTrue(AppRelease.sourceRepository.absoluteString.hasSuffix("gryonixNexus"))
        XCTAssertTrue(AppRelease.securityPolicy.absoluteString.contains("SECURITY.md"))
    }
    func testEveryDatapathRuntimeIsNotedAtTheVersionItIsBuiltAt() throws {
        let root = appleRoot.deletingLastPathComponent()
        let recipe = try String(contentsOf: root.appendingPathComponent("Tools/build-runtimes.sh"),
                                encoding: .utf8)
        let bridge = try String(contentsOf: root.appendingPathComponent("Android/xraybridge/go.mod"),
                                encoding: .utf8)

        let runtimes = OpenSourceLicense.all.filter { $0.source != .package }
        XCTAssertFalse(runtimes.isEmpty, "no runtime is listed, and four are linked")
        for runtime in runtimes {
            guard case .runtime(let pin) = runtime.source else { continue }
            XCTAssertTrue(recipe.contains(pin) || bridge.contains(pin),
                          "\(runtime.name) is noted at \(pin), which nothing builds")
        }
    }

    func testNoCopyleftComponentIsLinked() {
        let copyleft = OpenSourceLicense.all
            .filter { ["AGPL-3.0", "GPL-3.0", "GPL-2.0", "LGPL-3.0", "LGPL-2.1"].contains($0.terms) }
            .map(\.id)
        XCTAssertEqual(copyleft, [],
                       """
                       a GPL-family component was added to the notice list: \(copyleft). \
                       That decides the license of the whole app — LICENSE, THIRD-PARTY.md \
                       and the App Store submission all change with it.
                       """)
    }
}
