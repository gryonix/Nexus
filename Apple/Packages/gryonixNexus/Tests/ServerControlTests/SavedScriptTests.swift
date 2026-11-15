import XCTest
@testable import ServerControl

final class SavedScriptTests: XCTestCase {
    func testValidityAndAvailability() {
        let server = UUID()
        let everywhere = SavedScript(name: "Disk", body: "df -h")
        let scoped = SavedScript(name: "Logs", body: "journalctl -n 5", deploymentIDs: [server])
        XCTAssertTrue(everywhere.isValid)
        XCTAssertFalse(SavedScript(name: " ", body: "ls").isValid)
        XCTAssertFalse(SavedScript(name: "x", body: "\n").isValid)
        XCTAssertEqual(SavedScriptList.available(for: server, in: [everywhere, scoped]).count, 2)
        XCTAssertEqual(SavedScriptList.available(for: UUID(), in: [everywhere, scoped]), [everywhere])
    }

    func testTerminalInputAndExecCommand() {
        let script = SavedScript(name: "q", body: "echo 'it''s'\nls\n\n")
        XCTAssertEqual(script.terminalInput, "echo 'it''s'\nls\n")
        XCTAssertEqual(script.execCommand, "sh -c 'echo '\\''it'\\'''\\''s'\\''\nls\n\n'")
    }

    func testListEditsAndCoding() throws {
        let server = UUID()
        let one = SavedScript(name: "a", body: "x", deploymentIDs: [server])
        var two = SavedScript(name: "b", body: "y")
        var all = SavedScriptList.upserting(two, into: SavedScriptList.upserting(one, into: []))
        two.body = "z"
        all = SavedScriptList.upserting(two, into: all)
        XCTAssertEqual(all.map(\.body), ["x", "z"])
        XCTAssertEqual(SavedScriptList.forgettingServer(server, in: all)[0].deploymentIDs, [])
        XCTAssertEqual(SavedScriptList.removing(one.id, from: all), [two])
        XCTAssertEqual(try JSONDecoder().decode([SavedScript].self, from: JSONEncoder().encode(all)), all)
    }
}
