import ServerControl
import XCTest
@testable import gryonixNexus

@MainActor
final class TerminalMachineUsersTests: XCTestCase {
    private func pair() -> Deployment {
        Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.test",
                   entry: HostEndpoint(host: "203.0.113.10", user: "admin"),
                   homeWGAddress: "10.8.0.2")
    }

    private func defaults() -> UserDefaults {
        let name = "terminal-users-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    func testEachMachineSignsInAsTheAppUntilAnotherIsChosen() {
        let server = pair()
        let users = TerminalMachineUsers(deployment: server, defaults: defaults())
        let logins = TerminalMachinesSection.machineLogins(for: server, users: users)
        XCTAssertEqual(logins.map(\.username), ["admin", "admin"])
        XCTAssertEqual(logins.map(\.id), server.nodes.map(\.id))
    }

    func testAChosenAccountIsKeptAndHasItsOwnSession() throws {
        let server = pair()
        let store = defaults()
        let home = try XCTUnwrap(server.nodes.last)
        TerminalMachineUsers(deployment: server, defaults: store).choose("root", for: home)
        let again = TerminalMachineUsers(deployment: server, defaults: store)
        let logins = TerminalMachinesSection.machineLogins(for: server, users: again)
        XCTAssertEqual(logins.map(\.username), ["admin", "root"])
        XCTAssertNotEqual(logins.last?.id, home.id, "the root session must not reuse the app's")
        XCTAssertEqual(logins.last?.id, TerminalMachinesSection.profileID(home.id, "root"))
    }

    func testChoosingTheAppsOwnAccountForgetsTheChoice() throws {
        let server = pair()
        let store = defaults()
        let home = try XCTUnwrap(server.nodes.last)
        let users = TerminalMachineUsers(deployment: server, defaults: store)
        users.choose("root", for: home)
        users.choose("admin", for: home)
        XCTAssertNil(store.string(forKey: TerminalMachineUsers.key(server.id, home.id)))
        XCTAssertEqual(users.user(of: home), "admin")
    }
}
