import ServerControl
import XCTest

@testable import gryonixNexus

final class TerminalDirectHostTests: XCTestCase {
    private var fileURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("terminal-hosts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("terminal-hosts.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        try super.tearDownWithError()
    }

    private func store() -> TerminalDirectHostStore {
        TerminalDirectHostStore(fileURL: fileURL)
    }

    // MARK: - Storage

    func testSavingTheSameIdEditsTheRowAndADifferentIdAddsOne() throws {
        let store = store()
        let id = UUID()
        try store.upsert(TerminalDirectHost(id: id, name: "Desk", host: "10.0.0.4",
                                            username: "morgan"))
        try store.upsert(TerminalDirectHost(id: id, name: "Desk", host: "10.0.0.5",
                                            port: 2222, username: "root"))

        var hosts = try store.load()
        XCTAssertEqual(hosts.count, 1, "the same id is the same machine — an edit, not a second row")
        XCTAssertEqual(hosts.first?.host, "10.0.0.5")
        XCTAssertEqual(hosts.first?.port, 2222)
        XCTAssertEqual(hosts.first?.username, "root")

        try store.upsert(TerminalDirectHost(name: "Router", host: "10.0.0.1", username: "admin"))
        hosts = try store.load()
        XCTAssertEqual(hosts.count, 2, "a different id is a different machine")
        XCTAssertEqual(hosts.map(\.host), ["10.0.0.5", "10.0.0.1"])
    }

    /// Removal takes the named machine and nothing else
    func testRemovingOneHostLeavesTheOthersAlone() throws {
        let store = store()
        let keep = TerminalDirectHost(name: "Router", host: "10.0.0.1", username: "admin")
        let drop = TerminalDirectHost(name: "Desk", host: "10.0.0.4", username: "morgan")
        let alsoKeep = TerminalDirectHost(host: "vps.example.com", username: "root")
        for host in [keep, drop, alsoKeep] { try store.upsert(host) }

        try store.remove(id: drop.id)

        XCTAssertEqual(try store.load().map(\.id), [keep.id, alsoKeep.id])
    }

    func testAMissingFileLoadsAsNoHosts() throws {
        XCTAssertEqual(try store().load().count, 0)
    }

    // MARK: - What the row says

    func testTheTitleIsTheNameOrTheAddressButNeverEmpty() {
        XCTAssertEqual(TerminalDirectHost(name: "Desk", host: "10.0.0.4",
                                          username: "morgan").title, "Desk")
        XCTAssertEqual(TerminalDirectHost(name: "", host: "10.0.0.4",
                                          username: "morgan").title, "10.0.0.4")
        XCTAssertEqual(TerminalDirectHost(name: "   ", host: "10.0.0.4",
                                          username: "morgan").title, "10.0.0.4")
    }

    // MARK: - The bridge to everything that takes a deployment

    func testTheHostDialsWhereTheSheetSaid() {
        let host = TerminalDirectHost(name: "Desk", host: "10.0.0.4", port: 2222,
                                      username: "morgan")
        let config = host.deployment.dashboardConfig

        XCTAssertEqual(host.deployment.id, host.id,
                       "the id is the namespace its logins and its pinned key are stored under")
        XCTAssertEqual(config.vpsHost, "10.0.0.4")
        XCTAssertEqual(config.sshPort, 2222)
        XCTAssertEqual(config.sshUser, "morgan")
        XCTAssertTrue(config.isConnectable)
        XCTAssertEqual(host.deployment.topology, .singleHost,
                       "no relay, no home half — a direct host is one machine")
    }

    func testAHostWithNoAccountCannotBeDialled() {
        let named = TerminalDirectHost(host: "10.0.0.4", username: "morgan")
        let anonymous = TerminalDirectHost(host: "10.0.0.4", username: "")

        XCTAssertTrue(named.deployment.dashboardConfig.isConnectable)
        XCTAssertFalse(anonymous.deployment.dashboardConfig.isConnectable)
    }

    // MARK: - The credential half both sheets share

    func testThePlainAnswersComeBackAsThemselves() {
        var password = SSHSecretDraft(kind: .password)
        password.password = "hunter2"
        XCTAssertEqual(password.secret(), .password("hunter2"))

        var appKey = SSHSecretDraft(kind: .appKey)
        XCTAssertEqual(appKey.secret(), .appKey)
    }

    func testAnEmptyEditorOnAnEditKeepsTheStoredKey() {
        let seed = Data(repeating: 7, count: 32)
        var draft = SSHSecretDraft(editing: .privateKeySeed(seed))

        XCTAssertEqual(draft.kind, .privateKey)
        XCTAssertTrue(draft.pastedKey.isEmpty,
                      "the stored key is never put back in the box")
        XCTAssertEqual(draft.secret(keeping: .privateKeySeed(seed)), .privateKeySeed(seed))
        XCTAssertNil(draft.problem)
    }

    func testAnEmptyEditorWithNothingToKeepIsRefused() {
        var draft = SSHSecretDraft(kind: .privateKey)

        XCTAssertFalse(draft.isComplete, "Save stays disabled")
        XCTAssertNil(draft.secret(), "and asking anyway does not invent a key")
    }

    func testAKeyThatCannotBeReadIsRefusedWhereItWasPasted() {
        var draft = SSHSecretDraft(kind: .privateKey)
        draft.pastedKey = "-----BEGIN OPENSSH PRIVATE KEY-----\nnot a key\n-----END OPENSSH PRIVATE KEY-----"

        XCTAssertTrue(draft.isComplete, "the box is not empty, so Save is offered")
        XCTAssertNil(draft.secret(), "but nothing is stored")
        XCTAssertNotNil(draft.problem, "and the form says why, instead of the server saying no later")
    }

    func testARefusedKeyDoesNotDiscardTheOneAlreadyStored() {
        let seed = Data(repeating: 3, count: 32)
        var draft = SSHSecretDraft(kind: .privateKey)
        draft.pastedKey = "nonsense"

        XCTAssertNil(draft.secret(keeping: .privateKeySeed(seed)))
        XCTAssertNotNil(draft.problem)
    }
}
