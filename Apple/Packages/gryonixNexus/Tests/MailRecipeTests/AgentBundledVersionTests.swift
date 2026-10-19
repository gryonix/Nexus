import XCTest
@testable import MailRecipe

final class AgentBundledVersionTests: XCTestCase {
    private func cargoManifest() throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        // <this file> → MailRecipeTests → Tests → gryonixNexus → Packages → Apple
        for _ in 0 ..< 6 { url.deleteLastPathComponent() }
        let manifest = url
            .appendingPathComponent("Server")
            .appendingPathComponent("gryonixnexusd")
            .appendingPathComponent("Cargo.toml")
        let text = try String(contentsOf: manifest, encoding: .utf8)
        XCTAssertFalse(text.isEmpty, "found the manifest but it is empty: \(manifest.path)")
        return text
    }

    /// `version = "x.y.z"` from the `[package]` table, and only from there
    private func crateVersion(in manifest: String) -> String? {
        var inPackage = false
        for line in manifest.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inPackage = trimmed == "[package]"
                continue
            }
            guard inPackage, trimmed.hasPrefix("version = \"") else { continue }
            return String(trimmed.dropFirst("version = \"".count).dropLast())
        }
        return nil
    }

    func testTheBundledVersionIsTheCrateVersion() throws {
        let manifest = try cargoManifest()
        let crate = try XCTUnwrap(crateVersion(in: manifest),
                                  "no top-level `version = \"…\"` line in Cargo.toml")
        XCTAssertEqual(
            AgentBootstrapSections.bundledVersion, crate,
            "the app says it carries \(AgentBootstrapSections.bundledVersion) but the crate is \(crate) — "
                + "bump AgentBootstrapSections.bundledVersion together with Cargo.toml")
    }

    /// The harness must be able to fail
    func testTheHarnessActuallyReadsTheManifest() throws {
        let manifest = try cargoManifest()
        XCTAssertTrue(manifest.contains("name = \"gryonixnexusd\""),
                      "this is not the agent's manifest")
        XCTAssertTrue(manifest.contains("[package]"), "this is not a Cargo manifest")
        XCTAssertNotNil(crateVersion(in: manifest), "no version in the [package] table")
    }
}

final class AgentVersionTests: XCTestCase {
    func testTwoDigitComponentsBeatSingleDigitOnes() {
        XCTAssertTrue(AgentVersion.isNewer("0.0.82", than: "0.0.9"))
        XCTAssertFalse(AgentVersion.isNewer("0.0.9", than: "0.0.82"))
    }

    func testASecondBuildOfTheDayIsNewerThanTheFirst() {
        XCTAssertTrue(AgentVersion.isNewer("26.10.12-1", than: "26.10.12"))
        XCTAssertTrue(AgentVersion.isNewer("26.10.12-2", than: "26.10.12-1"))
        XCTAssertFalse(AgentVersion.isNewer("26.10.12-9", than: "26.10.13"))
    }

    func testADatedVersionBeatsTheOldNumbering() {
        XCTAssertTrue(AgentVersion.isNewer("26.10.11", than: "0.0.237"))
        XCTAssertTrue(AgentVersion.isNewer("26.11.1", than: "26.10.31"))
        XCTAssertFalse(AgentVersion.isNewer("0.0.237", than: "26.10.11"))
    }

    func testTheSameVersionIsNotAnUpdate() {
        XCTAssertFalse(AgentVersion.isNewer("0.0.82", than: "0.0.82"))
    }

    func testEarlierComponentsWinOverLaterOnes() {
        XCTAssertTrue(AgentVersion.isNewer("0.1.0", than: "0.0.99"))
        XCTAssertTrue(AgentVersion.isNewer("1.0.0", than: "0.99.99"))
        XCTAssertFalse(AgentVersion.isNewer("0.0.99", than: "0.1.0"))
    }

    func testAShorterVersionIsPaddedRatherThanRankedBelow() {
        XCTAssertFalse(AgentVersion.isNewer("0.1", than: "0.1.0"))
        XCTAssertFalse(AgentVersion.isNewer("0.1.0", than: "0.1"))
        XCTAssertTrue(AgentVersion.isNewer("0.1.1", than: "0.1"))
    }

    func testAnUnreadableVersionIsNeverAnUpdate() {
        XCTAssertFalse(AgentVersion.isNewer("0.0.82", than: ""))
        XCTAssertFalse(AgentVersion.isNewer("", than: "0.0.82"))
        XCTAssertFalse(AgentVersion.isNewer("0.0.82", than: "unknown"))
        XCTAssertFalse(AgentVersion.isNewer("nightly", than: "0.0.82"))
    }

    func testASuffixDoesNotDefeatTheComparison() {
        XCTAssertTrue(AgentVersion.isNewer("0.0.83-rc1", than: "0.0.82"))
    }
}
