import XCTest
@testable import VPNTunnel

final class SharedContainerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for name in ["legacy", "group"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name),
                                                    withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAMissingDirectoryIsCreated() {
        let fresh = root.appendingPathComponent("fresh/inner")
        XCTAssertTrue(SharedContainer.ensureExists(fresh))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    }

    func testADirectoryThatCannotBeMadeIsReportedRatherThanAssumed() throws {
        let blocker = root.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        XCTAssertFalse(SharedContainer.ensureExists(blocker.appendingPathComponent("inside")))
    }

    func testFilesWrittenBeforeTheGroupMoveIntoIt() throws {
        let legacy = root.appendingPathComponent("legacy")
        let group = root.appendingPathComponent("group")
        try Data("profiles".utf8).write(to: legacy.appendingPathComponent("vpn-profiles.json"))

        SharedContainer.adoptLegacyFiles(into: group, from: legacy)

        XCTAssertEqual(try String(contentsOf: group.appendingPathComponent("vpn-profiles.json"), encoding: .utf8),
                       "profiles")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("vpn-profiles.json").path))
    }

    func testAFileAlreadyInTheGroupIsNeverReplaced() throws {
        let legacy = root.appendingPathComponent("legacy")
        let group = root.appendingPathComponent("group")
        try Data("old".utf8).write(to: legacy.appendingPathComponent("vpn-sessions.json"))
        try Data("new".utf8).write(to: group.appendingPathComponent("vpn-sessions.json"))

        SharedContainer.adoptLegacyFiles(into: group, from: legacy)

        XCTAssertEqual(try String(contentsOf: group.appendingPathComponent("vpn-sessions.json"), encoding: .utf8),
                       "new")
    }
}
