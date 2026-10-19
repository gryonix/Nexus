import gryonixNexusCore
import ServerControl
import XCTest

@testable import gryonixNexus

final class InstallCredentialTests: XCTestCase {
    private let keychain = KeychainStore(service: "com.skaymer.gryonixnexus.installcredentialtests")
    private let deploymentID = UUID()
    private var nodeID = UUID()

    private var store: InstallCredentialStore {
        InstallCredentialStore(deploymentID: deploymentID, keychain: keychain)
    }

    override func tearDown() {
        store.deleteAll(nodeIDs: [nodeID])
        super.tearDown()
    }

    // MARK: - Storage

    func testASecretBelongsToOneMachineOnly() throws {
        try store.save(.password("relay-root"), for: .vps)

        XCTAssertEqual(store.secret(for: .vps), .password("relay-root"))
        XCTAssertNil(store.secret(for: .home), "the home half was never given one")

        try store.save(.password("home-user"), for: .home)
        XCTAssertEqual(store.secret(for: .vps), .password("relay-root"),
                       "storing the second must not overwrite the first")
        XCTAssertEqual(store.secret(for: .home), .password("home-user"))
    }

    func testAPastedKeyRoundTrips() throws {
        let seed = Data((0..<32).map { UInt8($0) })
        try store.save(.privateKeySeed(seed), for: .vps)
        XCTAssertEqual(store.secret(for: .vps), .privateKeySeed(seed))
    }

    func testSwitchingBackToTheAppKeyForgetsThePassword() throws {
        try store.save(.password("hunter2"), for: .vps)
        XCTAssertNotNil(store.secret(for: .vps))

        try store.save(.appKey, for: .vps)
        XCTAssertNil(store.secret(for: .vps))
    }

    func testErasingADeploymentTakesEveryMachinesSecret() throws {
        let node = SSHHostID(kind: .node(nodeID))
        try store.save(.password("relay"), for: .vps)
        try store.save(.password("home"), for: .home)
        try store.save(.password("third"), for: node)

        store.deleteAll(nodeIDs: [nodeID])

        XCTAssertNil(store.secret(for: .vps))
        XCTAssertNil(store.secret(for: .home))
        XCTAssertNil(store.secret(for: node), "a machine without a slot is still a machine")
    }

    // MARK: - The grant step

    @MainActor
    func testTheGrantStepGoesAwayWhenNothingSignsInWithTheAppKey() {
        let viewModel = InstallViewModel(deployment: singleHostDeployment(), bundle: singleHostBundle())
        XCTAssertEqual(viewModel.targets.count, 1)
        XCTAssertTrue(viewModel.needsAccessGrant, "the app key is still the default")

        viewModel.targets[0].secret = SSHSecretDraft(kind: .password)
        XCTAssertFalse(viewModel.needsAccessGrant)

        viewModel.targets[0].secret = SSHSecretDraft(kind: .privateKey)
        XCTAssertFalse(viewModel.needsAccessGrant, "an owner's own key is not the app's either")
    }

    @MainActor
    func testAnEmptyPasswordBlocksTheStart() {
        let viewModel = InstallViewModel(deployment: singleHostDeployment(), bundle: singleHostBundle())
        viewModel.targets[0].secret = SSHSecretDraft(kind: .password)
        XCTAssertFalse(viewModel.targets[0].secret.isComplete)

        viewModel.targets[0].secret.password = "hunter2"
        XCTAssertTrue(viewModel.targets[0].secret.isComplete)
    }

    @MainActor
    func testChangingTheCredentialUnchecksTheConnection() {
        let viewModel = InstallViewModel(deployment: singleHostDeployment(), bundle: singleHostBundle())
        let id = viewModel.targets[0].id
        viewModel.targets[0].connection = .ok

        viewModel.credentialChanged(id)

        XCTAssertEqual(viewModel.targets[0].connection, .unchecked)
    }

    // MARK: - Fixtures

    private func singleHostDeployment() -> Deployment {
        Deployment(id: deploymentID,
                   name: "example.com",
                   topology: .singleHost,
                   domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "server-user"))
    }

    private func singleHostBundle() -> GeneratedBundle {
        GeneratedBundle(artifacts: [
            Artifact(fileName: "setup-mail-server.sh",
                     kind: .shellScript,
                     contents: "#!/usr/bin/env bash\n# GRYONIXNEXUS_DISTRO: ubuntu\n",
                     summary: "setup",
                     server: .singleHost)
        ])
    }
}
