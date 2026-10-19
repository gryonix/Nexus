import ServerControl
import XCTest

@testable import gryonixNexus

final class ManagementPasswordTests: XCTestCase {
    private let keychain = KeychainStore(service: "com.skaymer.gryonixnexus.managementpasswordtests")
    private let deploymentID = UUID()

    private var store: DashboardPasswordStore {
        DashboardPasswordStore(deploymentID: deploymentID, keychain: keychain)
    }

    override func tearDown() {
        store.delete()
        try? keychain.delete("ssh-password-\(deploymentID.uuidString)")
        super.tearDown()
    }

    func testEachMachineKeepsItsOwnPassword() throws {
        try store.save("relay-secret", for: .vps)

        XCTAssertEqual(store.load(for: .vps), "relay-secret")
        XCTAssertNil(store.load(for: .home), "the home half was never given one")

        try store.save("home-secret", for: .home)
        XCTAssertEqual(store.load(for: .vps), "relay-secret", "the second must not overwrite the first")
        XCTAssertEqual(store.load(for: .home), "home-secret")
    }

    func testAPasswordStoredBeforeTheSplitAnswersOnlyForTheEntryMachine() throws {
        try keychain.set("legacy-pw", for: "ssh-password-\(deploymentID.uuidString)")

        XCTAssertEqual(store.load(for: .vps), "legacy-pw")
        XCTAssertNil(store.load(for: .home), "the entry machine's password is not sent to another one")

        // And a machine given its own password stops inheriting.
        try store.save("home-of-its-own", for: .home)
        XCTAssertEqual(store.load(for: .home), "home-of-its-own")
        XCTAssertEqual(store.load(for: .vps), "legacy-pw", "the other machine still inherits")
    }

    func testDeletingTakesTheInheritedPasswordToo() throws {
        try keychain.set("legacy-pw", for: "ssh-password-\(deploymentID.uuidString)")
        try store.save("relay-secret", for: .vps)

        store.delete()

        XCTAssertNil(store.load(for: .vps))
        XCTAssertNil(store.load(for: .home))
    }

    // MARK: - Moving a server to another device

    private final class MemoryStore: DeploymentStore {
        var saved: [Deployment] = []
        func load() throws -> [Deployment] { saved }
        func save(_ deployments: [Deployment]) throws { saved = deployments }
    }

    private let source = KeychainStore(service: "com.skaymer.gryonixnexus.managementpasswordtests.source")
    private let destination = KeychainStore(service: "com.skaymer.gryonixnexus.managementpasswordtests.destination")

    private func pair() -> Deployment {
        Deployment(id: deploymentID,
                   name: "pair",
                   topology: .vpsRelayWithHomeBackend,
                   domain: "pair.example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "server-user"),
                   homeWGAddress: "10.8.0.2")
    }

    /// A pair moved to another device arrives with BOTH passwords
    func testMovingAPairCarriesBothPasswords() throws {
        let deployment = pair()
        let sourceStore = DashboardPasswordStore(deploymentID: deployment.id, keychain: source)
        defer {
            sourceStore.delete()
            DashboardPasswordStore(deploymentID: deployment.id, keychain: destination).delete()
        }
        try sourceStore.save("relay-secret", for: .vps)
        try sourceStore.save("home-secret", for: .home)

        let bundle = DeploymentTransferService.export(deployment, keychain: source)
        XCTAssertEqual(bundle.dashboardPasswords?["vps"], "relay-secret")
        XCTAssertEqual(bundle.dashboardPasswords?["home"], "home-secret")
        XCTAssertEqual(bundle.dashboardPassword, "relay-secret",
                       "the old field still describes the entry machine for older builds")

        let data = try DeploymentTransferService.encode(bundle)
        try DeploymentTransferService.apply(try DeploymentTransferService.decode(data),
                                            store: MemoryStore(), keychain: destination)

        let moved = DashboardPasswordStore(deploymentID: deployment.id, keychain: destination)
        XCTAssertEqual(moved.load(for: .vps), "relay-secret")
        XCTAssertEqual(moved.load(for: .home), "home-secret")
    }

    func testAnOlderBundlesSinglePasswordCoversEveryMachine() throws {
        let deployment = pair()
        defer { DashboardPasswordStore(deploymentID: deployment.id, keychain: destination).delete() }
        var bundle = DeploymentTransferService.export(deployment, keychain: source)
        bundle.dashboardPassword = "one-for-both"
        bundle.dashboardPasswords = nil

        try DeploymentTransferService.apply(bundle, store: MemoryStore(), keychain: destination)

        let moved = DashboardPasswordStore(deploymentID: deployment.id, keychain: destination)
        XCTAssertEqual(moved.load(for: .vps), "one-for-both")
        XCTAssertEqual(moved.load(for: .home), "one-for-both")
    }
}
