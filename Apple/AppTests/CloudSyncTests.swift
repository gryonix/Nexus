import ServerControl
import XCTest

@testable import gryonixNexus

/// Two devices sharing one iCloud Keychain
@MainActor
final class CloudSyncAppTests: XCTestCase {
    private final class MemoryStore: DeploymentStore, @unchecked Sendable {
        var saved: [Deployment] = []
        func load() throws -> [Deployment] { saved }
        func save(_ deployments: [Deployment]) throws { saved = deployments }
    }

    @MainActor
    private struct Device {
        let store = MemoryStore()
        let sync: CloudSync

        init(cloud: MemoryCloudItems, name: String) {
            let own = "cloud-sync-tests-\(name)-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: own)!
            sync = CloudSync(items: cloud, store: store, localKeys: KeychainStore(service: own),
                             defaults: defaults, tunnels: { nil })
        }
    }

    private let cloud = MemoryCloudItems()
    private let server = Deployment(name: "orion", topology: .singleHost, domain: "example.net",
                                    entry: HostEndpoint(host: "203.0.113.10", user: "server-user"))

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(false, forKey: DemoServer.enabledKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: DemoServer.enabledKey)
        super.tearDown()
    }

    func testANewDeviceGetsTheServer() async throws {
        let phone = Device(cloud: cloud, name: "phone")
        let mac = Device(cloud: cloud, name: "mac")
        try phone.store.upsert(server)
        phone.sync.choose(.apple)
        mac.sync.choose(.apple)
        await phone.sync.sync()
        await mac.sync.sync()
        XCTAssertEqual(try mac.store.load().map(\.name), ["orion"])
    }

    func testADeletionStaysOnTheDeviceThatMadeIt() async throws {
        let phone = Device(cloud: cloud, name: "phone")
        let mac = Device(cloud: cloud, name: "mac")
        try phone.store.upsert(server)
        phone.sync.choose(.apple)
        mac.sync.choose(.apple)
        await phone.sync.sync()
        await mac.sync.sync()
        try phone.store.remove(id: server.id)
        await phone.sync.sync()
        await mac.sync.sync()
        await phone.sync.sync()
        XCTAssertEqual(try mac.store.load().map(\.name), ["orion"])
        XCTAssertEqual(try phone.store.load(), [])
        XCTAssertNotNil(cloud.items["server.\(server.id.uuidString)"])
    }

    func testAPasswordSealsTheServerAndAnotherDeviceNeedsIt() async throws {
        let phone = Device(cloud: cloud, name: "phone")
        let mac = Device(cloud: cloud, name: "mac")
        try phone.store.upsert(server)
        phone.sync.choose(.applePassword)
        try await phone.sync.enter(password: "correct horse")
        await phone.sync.sync()
        let stored = try XCTUnwrap(cloud.items["server.\(server.id.uuidString)"])
        XCTAssertNil(String(decoding: stored, as: UTF8.self).range(of: "orion"))

        mac.sync.choose(.applePassword)
        await mac.sync.sync()
        XCTAssertEqual(mac.sync.status, .needsPassword)
        XCTAssertEqual(try mac.store.load(), [])
        try await mac.sync.enter(password: "correct horse")
        await mac.sync.sync()
        XCTAssertEqual(try mac.store.load().map(\.name), ["orion"])
    }

    func testServersOnlyLeavesTheKeysOut() throws {
        var transfer = DeploymentTransferService.export(server)
        transfer.sshIdentitySeed = Data([1, 2, 3])
        transfer.dashboardPasswords = ["vps": "secret"]
        let stripped = CloudSyncRun.withoutSecrets(transfer)
        XCTAssertNil(stripped.sshIdentitySeed)
        XCTAssertNil(stripped.dashboardPasswords)
        XCTAssertEqual(stripped.deployment, server)
    }

    func testOffSyncsNothing() async throws {
        let phone = Device(cloud: cloud, name: "phone")
        try phone.store.upsert(server)
        await phone.sync.sync()
        XCTAssertTrue(cloud.items.isEmpty)
    }
}
