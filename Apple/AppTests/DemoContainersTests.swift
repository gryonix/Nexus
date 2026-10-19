import AgentControl
import ServerControl
import AgentClient
import XCTest

@testable import gryonixNexus

@available(macOS 15.0, *)
@MainActor
final class DemoContainersTests: XCTestCase {
    private var deployment: Deployment {
        DemoServer.deployments().first!
    }

    override func setUp() async throws {
        try await super.setUp()
        await DemoAgentState.shared.forgetEverything()
    }

    private func operations() throws -> AgentContainerOperations {
        AgentContainerOperations(client: try XCTUnwrap(DemoAgent.client(for: deployment)))
    }

    func testADemoServerAnswersInsteadOfSpinningForever() async throws {
        let inventory = try await operations().inventory()
        XCTAssertFalse(inventory.groups.isEmpty)
        XCTAssertNil(inventory.unavailableReason)
    }

    func testTheFleetShowsAStackTheAppDidNotInstall() async throws {
        let groups = try await operations().inventory().groups
        XCTAssertTrue(groups.contains { $0.serviceID == nil },
                      "a demo with no stranger's stack demonstrates nothing")
        XCTAssertTrue(groups.contains { $0.serviceID != nil },
                      "and the app's own services stay listed and marked")
    }

    func testStoppingAGroupIsVisibleOnTheNextRead() async throws {
        let ops = try operations()
        let inventory = try await ops.inventory()
        let target = try XCTUnwrap(inventory.groups.first)
        XCTAssertEqual(target.status, .running)

        try await ops.control(key: target.key, action: .stop)

        let reread = try await ops.inventory()
        let after = try XCTUnwrap(reread.groups.first { $0.key == target.key })
        XCTAssertEqual(after.status, .stopped, "the imitation works on the next READ, not on a return code")
        XCTAssertTrue(after.containers.allSatisfy { $0.state == "exited" },
                      "a group that says stopped over running containers contradicts itself")
    }

    func testStartingItAgainBringsItBack() async throws {
        let ops = try operations()
        let first = try await ops.inventory()
        let key = try XCTUnwrap(first.groups.first?.key)
        try await ops.control(key: key, action: .stop)
        try await ops.control(key: key, action: .start)
        let reread = try await ops.inventory()
        let after = try XCTUnwrap(reread.groups.first { $0.key == key })
        XCTAssertEqual(after.status, .running)
    }

    func testRenamingSticksAndClearingGivesTheDetectedNameBack() async throws {
        let ops = try operations()
        let start = try await ops.inventory()
        let target = try XCTUnwrap(start.groups.first)

        _ = try await ops.rename(key: target.key, to: "  My stack  ")
        var renamed = try await ops.inventory()
        var group = try XCTUnwrap(renamed.groups.first { $0.key == target.key })
        XCTAssertEqual(group.displayName, "My stack", "a pasted name arrives with whitespace")
        XCTAssertTrue(group.isRenamed)
        XCTAssertEqual(group.derivedName, target.derivedName,
                       "the detected name always travels, so the way back needs no second call")

        _ = try await ops.rename(key: target.key, to: "")
        renamed = try await ops.inventory()
        group = try XCTUnwrap(renamed.groups.first { $0.key == target.key })
        XCTAssertEqual(group.displayName, target.derivedName)
        XCTAssertFalse(group.isRenamed)
    }

    func testTheDetailShowsAMaskedValueRatherThanSomethingUsable() async throws {
        let ops = try operations()
        let listing = try await ops.inventory()
        let name = try XCTUnwrap(listing.groups.first?.containers.first?.name)
        let detail = try await ops.inspect(container: name)
        let secret = try XCTUnwrap(detail.environment.first { $0.isSensitive })
        XCTAssertFalse(secret.value.contains(where: \.isLetter),
                       "a demo secret that looks like a password is one somebody will try to use")
    }

    func testTwoDemoServersDoNotShowTheSameStack() async throws {
        let servers = DemoServer.deployments()
        guard servers.count > 1 else { return XCTFail("the demo fleet is more than one server") }
        let first = AgentContainerOperations(client: try XCTUnwrap(DemoAgent.client(for: servers[0])))
        let second = AgentContainerOperations(client: try XCTUnwrap(DemoAgent.client(for: servers[1])))
        let a = try await first.inventory().groups.map(\.key)
        let b = try await second.inventory().groups.map(\.key)
        XCTAssertNotEqual(a, b, "each server's list follows the services that server carries")
    }

    func testCatalogServicesAreShownByDefault() {
        let defaults = UserDefaults(suiteName: "containers.preferences.test")!
        defaults.removePersistentDomain(forName: "containers.preferences.test")
        XCTAssertTrue(ContainersPreferences(defaults: defaults).showsCatalogServices)
    }
}
