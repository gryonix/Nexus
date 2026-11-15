import XCTest
@testable import MailRecipe

final class AgentBundledVersionTests: XCTestCase {
    /// What the packing script wrote beside the shipped archive
    private func packedVersion() throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        // <this file> → MailRecipeTests → Tests → gryonixNexus → Packages → Apple
        for _ in 0 ..< 5 { url.deleteLastPathComponent() }
        let file = url.appendingPathComponent("App/Resources/agent-src.version")
        return try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testTheBundledVersionIsThePackedOne() throws {
        let packed = try packedVersion()
        XCTAssertEqual(
            AgentBootstrapSections.bundledVersion, packed,
            "the app says it carries \(AgentBootstrapSections.bundledVersion) but packs \(packed) — "
                + "the app carries the agent on main of nexus-agent; set bundledVersion to that")
    }

    /// The harness must be able to fail
    func testTheHarnessActuallyReadsThePackedVersion() throws {
        let packed = try packedVersion()
        XCTAssertNotNil(AgentVersion.components(packed), "agent-src.version holds no version: \(packed)")
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

    func testNovemberCountersSortBelowTheDate() {
        let nov9 = Date(timeIntervalSince1970: 1_794_182_400)
        XCTAssertTrue(AgentVersion.isNewer("26.11.9", than: "26.11.25", now: nov9))
        XCTAssertFalse(AgentVersion.isNewer("26.11.25", than: "26.11.9", now: nov9))
        XCTAssertTrue(AgentVersion.isNewer("26.11.9-1", than: "26.11.9", now: nov9))
        XCTAssertTrue(AgentVersion.isNewer("26.11.10", than: "26.11.9", now: nov9.addingTimeInterval(86_400)))
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
