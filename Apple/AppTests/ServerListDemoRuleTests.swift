import ServerControl
import XCTest

@testable import gryonixNexus

@MainActor
final class ServerListDemoRuleTests: XCTestCase {
    /// The store the view model writes to, in memory
    private final class MemoryStore: DeploymentStore, @unchecked Sendable {
        var saved: [Deployment]
        init(_ deployments: [Deployment] = []) { saved = deployments }
        func load() throws -> [Deployment] { saved }
        func save(_ deployments: [Deployment]) throws { saved = deployments }
    }

    private func server(_ name: String) -> Deployment {
        Deployment(name: name, topology: .singleHost,
                   domain: name, entry: HostEndpoint(host: "203.0.113.77", user: "root"))
    }

    func testAnEmptyListFollowsTheDemoSwitch() {
        let model = ServerListViewModel(store: MemoryStore())
        model.load()
        if DemoServer.isEnabled {
            XCTAssertEqual(model.deployments.map(\.id), DemoServer.deployments().map(\.id),
                           "a fresh install — App Review's included — has nothing else to show")
        } else {
            XCTAssertTrue(model.deployments.isEmpty,
                          "with the demo off nothing invented may reach the list")
        }
    }

    func testAServerOfTheOwnersOwnLeavesNoDemoOnScreen() {
        let model = ServerListViewModel(store: MemoryStore([server("example.net")]))
        model.load()
        XCTAssertEqual(model.deployments.map(\.name), ["example.net"])
        XCTAssertFalse(model.deployments.contains { DemoServer.isDemo($0) })
    }

    func testTheDemoLeavesWhenTheFirstServerIsAddedAndReturnsWhenTheLastIsDeleted() throws {
        try XCTSkipUnless(DemoServer.isEnabled, "the demo fleet is switched off")
        let model = ServerListViewModel(store: MemoryStore())
        model.load()
        XCTAssertTrue(model.deployments.allSatisfy { DemoServer.isDemo($0) })

        let own = server("example.net")
        model.upsert(own)
        XCTAssertEqual(model.deployments.map(\.name), ["example.net"],
                       "adding a real server has to take the invented ones off the screen at once")

        model.delete(own)
        XCTAssertTrue(model.deployments.allSatisfy { DemoServer.isDemo($0) },
                      "and deleting the last one has to bring them back")
    }

    /// The demo is a VIEW, never a record
    func testReorderingTheDemoStoresNothing() throws {
        try XCTSkipUnless(DemoServer.isEnabled, "the demo fleet is switched off")
        let store = MemoryStore()
        let model = ServerListViewModel(store: store)
        model.load()
        model.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertTrue(store.saved.isEmpty, "stored: \(store.saved.map(\.name))")
    }

    func testAnAppearanceChangeToADemoCardSurvivesTheDemoRule() {
        let defaults = UserDefaults.standard
        let wasEnabled = defaults.bool(forKey: DemoServer.enabledKey)
        defaults.set(true, forKey: DemoServer.enabledKey)
        defer { defaults.set(wasEnabled, forKey: DemoServer.enabledKey) }

        let store = MemoryStore()
        let model = ServerListViewModel(store: store)
        model.load()
        guard var card = model.deployments.first else {
            return XCTFail("the demo fleet is on and the list is empty")
        }
        XCTAssertNil(card.cardSize, "the demo fleet starts on the app-wide default")

        card.cardSize = .compact
        card.tintName = ServerTint.red.rawValue
        model.updateAppearance(card)

        XCTAssertEqual(model.deployments.first?.cardSize, .compact,
                       "the change was applied and then overwritten by the rebuilt demo fleet")
        XCTAssertEqual(model.deployments.first?.tintName, ServerTint.red.rawValue)

        model.load()
        XCTAssertEqual(model.deployments.first?.cardSize, .compact,
                       "a reload rebuilt the invented fleet and lost the change again")

        XCTAssertTrue(store.saved.isEmpty, "stored: \(store.saved.map(\.name))")
    }

    func testReorderingRealServersStillStoresThem() {
        let store = MemoryStore([server("a.example.com"), server("b.example.com")])
        let model = ServerListViewModel(store: store)
        model.load()
        model.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(store.saved.map(\.name), ["b.example.com", "a.example.com"])
    }
}
