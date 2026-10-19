import ServerControl
import XCTest

@testable import gryonixNexus

@MainActor
final class ServerTransferModelTests: XCTestCase {
    private final class MemoryStore: DeploymentStore, @unchecked Sendable {
        var saved: [Deployment]
        init(_ deployments: [Deployment] = []) { saved = deployments }
        func load() throws -> [Deployment] { saved }
        func save(_ deployments: [Deployment]) throws { saved = deployments }
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(false, forKey: DemoServer.enabledKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: DemoServer.enabledKey)
        super.tearDown()
    }

    private let server = Deployment(name: "Home", topology: .singleHost, domain: "home.example",
                                    entry: HostEndpoint(host: "203.0.113.9", user: "admin"))

    private func file(_ deployment: Deployment, seed: Data? = nil) throws -> Data {
        try DeploymentTransferService.encode(DeploymentTransfer(
            deployment: deployment, sshIdentitySeed: seed, dashboardPassword: nil, wireGuardSeeds: [:],
            hostKeyPins: [:], reports: [], configuration: nil, homeLANAddress: nil,
            accessCredentials: nil, installUsers: nil, dashboardPasswords: nil))
    }

    func testASealedFileAsksForItsPassphraseFirst() throws {
        let list = ServerListViewModel(store: MemoryStore())
        let model = ServerTransferModel()
        let sealed = try TransferSeal.seal(try file(server), passphrase: "long enough")

        model.received(sealed, into: list)
        guard case .unlock = model.prompt else { return XCTFail("no passphrase was asked") }

        model.unlock(sealed, passphrase: "wrong one", into: list)
        XCTAssertNotNil(model.promptError)
        XCTAssertTrue(list.deployments.isEmpty)

        model.unlock(sealed, passphrase: "long enough", into: list)
        XCTAssertNil(model.prompt)
        XCTAssertEqual(list.deployments.map(\.id), [server.id])
    }

    func testAServerOfSeveralMachinesExportsItsOwnKey() {
        let ingress = DeploymentNode(id: UUID(), endpoint: HostEndpoint(host: "203.0.113.9", user: "admin"),
                                     capabilities: [.ingress])
        let worker = DeploymentNode(id: UUID(), endpoint: HostEndpoint(host: "192.0.2.5", user: "admin"),
                                    capabilities: [.worker], routedThrough: ingress.id)
        let pair = Deployment(name: "Pair", topology: .vpsRelayWithHomeBackend, entry: ingress.endpoint,
                              storedNodes: [ingress, worker])

        XCTAssertFalse(ServerListViewModel.usesOneTimeKey(for: pair))
        XCTAssertTrue(ServerListViewModel.usesOneTimeKey(for: server))
    }

    func testAFileWithoutAKeyOrPasswordSaysItCannotConnect() throws {
        let list = ServerListViewModel(store: MemoryStore())
        ServerTransferModel().received(try file(server), into: list)
        XCTAssertEqual(list.deployments.map(\.id), [server.id])
        XCTAssertNotNil(list.errorMessage)
    }

    func testAFileWithAKeyImportsWithoutAWarning() throws {
        let list = ServerListViewModel(store: MemoryStore())
        ServerTransferModel().received(try file(server, seed: Data(repeating: 1, count: 32)), into: list)
        XCTAssertEqual(list.deployments.map(\.id), [server.id])
        XCTAssertNil(list.errorMessage)
    }

    func testAServerAlreadyHereIsReplacedOnlyAfterAsking() throws {
        let list = ServerListViewModel(store: MemoryStore([server]))
        list.deployments = [server]
        let model = ServerTransferModel()
        var renamed = server
        renamed.name = "From the file"

        model.received(try file(renamed), into: list)
        XCTAssertEqual(model.replacing?.deployment.id, server.id)
        XCTAssertEqual(list.deployments.first?.name, "Home")

        model.confirmReplace(into: list)
        XCTAssertEqual(list.deployments.first?.name, "From the file")
    }
}
