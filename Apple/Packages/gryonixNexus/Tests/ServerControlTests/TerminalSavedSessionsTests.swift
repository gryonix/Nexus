import XCTest
@testable import ServerControl

final class TerminalSavedSessionsTests: XCTestCase {
    private func record(_ name: String, deployment: UUID = UUID()) -> SavedTerminalSession {
        SavedTerminalSession(profileID: UUID(), deploymentID: deployment, nodeID: nil, username: name)
    }

    func testOpenSelectsAndKeepsOrder() {
        var sessions = SavedTerminalSessions()
        let a = record("a"), b = record("b")
        sessions.open(a)
        sessions.open(b)
        sessions.open(a)
        XCTAssertEqual(sessions.records.map(\.username), ["a", "b"])
        XCTAssertEqual(sessions.selected, a.profileID)
    }

    func testCloseMovesSelectionToLast() {
        var sessions = SavedTerminalSessions()
        let a = record("a"), b = record("b")
        sessions.open(a)
        sessions.open(b)
        sessions.close(profileID: b.profileID)
        XCTAssertEqual(sessions.selectedRecord?.username, "a")
    }

    func testCloseAllForDeployment() {
        var sessions = SavedTerminalSessions()
        let server = UUID()
        sessions.open(record("a", deployment: server))
        sessions.open(record("b", deployment: server))
        sessions.open(record("c"))
        sessions.select(sessions.records[0].profileID)
        sessions.closeAll(deploymentID: server)
        XCTAssertEqual(sessions.records.map(\.username), ["c"])
        XCTAssertEqual(sessions.selectedRecord?.username, "c")
    }

    func testEncodeDecodeRoundTrip() throws {
        var sessions = SavedTerminalSessions()
        sessions.open(SavedTerminalSession(profileID: UUID(), deploymentID: UUID(),
                                           nodeID: UUID(), username: "root"))
        sessions.open(record("deploy"))
        let data = try JSONEncoder().encode(sessions)
        XCTAssertEqual(try JSONDecoder().decode(SavedTerminalSessions.self, from: data), sessions)
    }

    func testStoreRoundTripOnDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "saved-sessions-\(UUID())"))
        let store = SavedTerminalSessionsStore(defaults: defaults)
        XCTAssertTrue(store.load().records.isEmpty)
        var sessions = SavedTerminalSessions()
        sessions.open(record("x"))
        store.save(sessions)
        XCTAssertEqual(store.load(), sessions)
    }

    func testTmuxCommandNamesSessionByProfile() {
        let id = UUID(uuidString: "ABCDEF12-0000-0000-0000-000000000000")!
        let command = TerminalTmux.launchCommand(profileID: id)
        XCTAssertTrue(command.contains("tmux new -A -s gryonix-abcdef12"))
        XCTAssertTrue(command.hasSuffix("\r"))
    }
}
