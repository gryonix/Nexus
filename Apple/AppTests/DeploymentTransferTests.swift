import ServerControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

/// Moving a server to another device
@MainActor
final class DeploymentTransferTests: XCTestCase {
    private final class MemoryStore: DeploymentStore, @unchecked Sendable {
        var saved: [Deployment] = []
        func load() throws -> [Deployment] { saved }
        func save(_ deployments: [Deployment]) throws { saved = deployments }
    }

    private var source = KeychainStore(service: "com.skaymer.gryonixnexus.transfertests.source")
    private var destination = KeychainStore(service: "com.skaymer.gryonixnexus.transfertests.destination")
    private var deployment = Deployment(name: "b5", topology: .singleHost, domain: "b5.example.net",
                                        entry: HostEndpoint(host: "203.0.113.10", user: "server-user"))

    override func tearDown() async throws {
        for keychain in [source, destination] {
            let id = deployment.id
            try? KeychainSSHIdentityStore(deploymentID: id, keychain: keychain).delete()
            PendingTransferStore(deploymentID: id, keychain: keychain).clear()
            DashboardPasswordStore(deploymentID: id, keychain: keychain).delete()
            AccessCredentialStore(deploymentID: id, keychain: keychain).save([:])
            DeploymentReportStore(deploymentID: id, keychain: keychain).delete()
        }
        try await super.tearDown()
    }

    private func seedSource() {
        let id = deployment.id
        try? KeychainSSHIdentityStore(deploymentID: id, keychain: source)
            .save(AppSSHIdentity(privateKeySeed: Data(repeating: 7, count: 32)))
        try? DashboardPasswordStore(deploymentID: id, keychain: source).save("dashboard-pw")
        HostKeyPinStore(deploymentID: id, keychain: source).store("ssh-ed25519 AAAA-vps", for: .vps)
        DeploymentReportStore(deploymentID: id, keychain: source)
            .save(host: "b5.example.net", text: "REPORT BODY")
        AccessCredentialStore(deploymentID: id, keychain: source).save([
            "vault|Vaultwarden": AccessCredential(login: "me@example.com",
                                                  password: "the-master-password",
                                                  token: nil)
        ])
    }

    private func moveToDestination() throws {
        let bundle = DeploymentTransferService.export(deployment, keychain: source)
        let data = try DeploymentTransferService.encode(bundle)
        let decoded = try DeploymentTransferService.decode(data)
        try DeploymentTransferService.apply(decoded, store: MemoryStore(), keychain: destination)
    }

    func testTheOwnersOwnRecordedPasswordsSurviveTheMove() throws {
        seedSource()
        try moveToDestination()

        let moved = AccessCredentialStore(deploymentID: deployment.id, keychain: destination).load()
        XCTAssertEqual(moved["vault|Vaultwarden"]?.password, "the-master-password",
                       "a password the owner typed is not written down anywhere else — losing it is losing it")
        XCTAssertEqual(moved["vault|Vaultwarden"]?.login, "me@example.com")
    }

    func testEverySecretTheBundleCarriesArrives() throws {
        seedSource()
        try moveToDestination()
        let id = deployment.id

        XCTAssertEqual(try? KeychainSSHIdentityStore(deploymentID: id, keychain: destination).load()?.privateKeySeed,
                       Data(repeating: 7, count: 32),
                       "without the SSH key the moved server cannot be reached at all")
        XCTAssertEqual(DashboardPasswordStore(deploymentID: id, keychain: destination).load(), "dashboard-pw")
        XCTAssertEqual(HostKeyPinStore(deploymentID: id, keychain: destination).pin(for: .vps),
                       "ssh-ed25519 AAAA-vps",
                       "a lost pin means the copy re-trusts whatever key it is shown")
        XCTAssertEqual(DeploymentReportStore(deploymentID: id, keychain: destination).load().first?.text,
                       "REPORT BODY")
    }

    func testTheDeploymentKeepsItsIdentity() throws {
        seedSource()
        let store = MemoryStore()
        let bundle = DeploymentTransferService.export(deployment, keychain: source)
        let decoded = try DeploymentTransferService.decode(try DeploymentTransferService.encode(bundle))
        try DeploymentTransferService.apply(decoded, store: store, keychain: destination)

        XCTAssertEqual(store.saved.first?.id, deployment.id)
    }

    func testAnOlderBundleLeavesExistingOverridesAlone() throws {
        seedSource()
        let id = deployment.id
        AccessCredentialStore(deploymentID: id, keychain: destination).save([
            "vault|Vaultwarden": AccessCredential(login: "already-here", password: "keep-me", token: nil)
        ])

        var bundle = DeploymentTransferService.export(deployment, keychain: source)
        bundle.accessCredentials = nil          // what an older build wrote
        try DeploymentTransferService.apply(bundle, store: MemoryStore(), keychain: destination)

        XCTAssertEqual(AccessCredentialStore(deploymentID: id, keychain: destination).load()["vault|Vaultwarden"]?.password,
                       "keep-me")
    }

    func testANewerBundleIsRefused() throws {
        seedSource()
        var bundle = DeploymentTransferService.export(deployment, keychain: source)
        bundle.version = DeploymentTransfer.currentVersion + 1
        let data = try DeploymentTransferService.encode(bundle)
        XCTAssertThrowsError(try DeploymentTransferService.decode(data))
    }

    func testAFileWithAOneTimeKeyDoesNotCarryTheLongLivedKey() throws {
        seedSource()
        let oneTime = Data(repeating: 9, count: 32)
        let bundle = DeploymentTransferService.export(deployment, transferKey: (oneTime, "ab12"), keychain: source)
        XCTAssertEqual(bundle.sshIdentitySeed, oneTime)
        XCTAssertEqual(bundle.sshTransferID, "ab12")
        XCTAssertNotEqual(bundle.sshIdentitySeed, Data(repeating: 7, count: 32))
    }

    func testImportingAOneTimeKeyRemembersItsId() throws {
        seedSource()
        let oneTime = Data(repeating: 9, count: 32)
        let bundle = DeploymentTransferService.export(deployment, transferKey: (oneTime, "ab12"), keychain: source)
        try DeploymentTransferService.apply(bundle, store: MemoryStore(), keychain: destination)
        let pending = PendingTransferStore(deploymentID: deployment.id, keychain: destination)
        XCTAssertEqual(pending.load(), "ab12")
        XCTAssertEqual(try KeychainSSHIdentityStore(deploymentID: deployment.id, keychain: destination).load()?.privateKeySeed, oneTime)
        pending.clear()
        XCTAssertNil(pending.load())
    }

    func testTheFormatIsStillVersionOne() throws {
        seedSource()
        let bundle = DeploymentTransferService.export(deployment, keychain: source)
        XCTAssertEqual(bundle.version, 1)
    }
}

/// The agent sources the app carries
final class AgentSourcesResourceTests: XCTestCase {
    func testTheAppCarriesTheAgentSources() throws {
        let data = try AgentBootstrapOperations.sourceArchive()
        XCTAssertGreaterThan(data.count, 100_000,
                             "a tree this small is not the agent — the build phase produced something empty")
        XCTAssertLessThan(data.count, 20_000_000,
                          "far too big: `target/` almost certainly got in, which is gigabytes on a developer machine")
    }

    func testTheResourceIsAGzipArchive() throws {
        let data = try AgentBootstrapOperations.sourceArchive()
        XCTAssertEqual(Array(data.prefix(2)), [0x1f, 0x8b])
    }
}
