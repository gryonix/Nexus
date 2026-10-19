import AgentClient
import AgentControl
import ServerControl
import XCTest

@testable import gryonixNexus

final class AccessVaultTests: XCTestCase {
    func testMailboxIdentityMatchesAndroidAndEditsKeepItsID() {
        let first = AccessVaultEntry.mailbox(host: "single", address: "Owner@Example.Test", password: "one",
                                           at: Date(timeIntervalSince1970: 1), writer: "phone")
        let changed = AccessVaultEntry.mailbox(host: "single", address: "owner@example.test", password: "two",
                                             at: Date(timeIntervalSince1970: 2), writer: "other")
        XCTAssertEqual(first.id, "single|Mailbox: owner@example.test")
        XCTAssertEqual(first.login, "owner@example.test")
        XCTAssertEqual(first.updatedAt, 1000)
        XCTAssertEqual(first.id, changed.id)
        XCTAssertEqual(changed.password, "two")
    }

    private func remote(_ id: String, host: String = "single", title: String = "Vaultwarden",
                        login: String = "admin@example.com", password: String,
                        at: Int64, by: String = "phone-b",
                        deleted: Bool = false) -> Gryonixnexusd_V1_VaultEntry {
        var entry = AccessVaultEntry.make(id: id, host: host, title: title,
                                          website: "https://vault.example.com",
                                          login: login, password: password, token: "",
                                          updatedAt: Date(timeIntervalSince1970: Double(at) / 1000),
                                          updatedBy: by)
        entry.deleted = deleted
        return entry
    }

    private func local(_ host: String = "single", _ title: String = "Vaultwarden",
                       password: String, at: Int64) -> EditableAccount {
        EditableAccount(host: host, title: title, website: "https://vault.example.com",
                        reportLogin: "admin@example.com", reportPassword: "from-report",
                        reportToken: "", login: "admin@example.com", password: password,
                        token: "", hasToken: false, isVaultwarden: true,
                        updatedAt: at, updatedBy: "phone-a")
    }

    private let deployment = Deployment(name: "test", topology: .singleHost, domain: "example.com",
                                        entry: HostEndpoint(host: "203.0.113.10", user: "server-user"))

    func testAnAccountOnlyTheServerHasIsShown() {
        let merged = InstallReportView.merged(
            local: [],
            remote: [remote("single|AdGuard Home", title: "AdGuard Home", password: "hunter2", at: 100)],
            deployment: deployment)
        XCTAssertEqual(merged.map(\.title), ["AdGuard Home"])
        XCTAssertEqual(merged.first?.password, "hunter2")
        XCTAssertEqual(merged.first?.reportPassword, "")
    }

    func testTheServersNewerValueReplacesThisDevices() {
        let merged = InstallReportView.merged(
            local: [local(password: "old-here", at: 100)],
            remote: [remote("single|Vaultwarden", password: "changed-elsewhere", at: 200)],
            deployment: deployment)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.password, "changed-elsewhere")
        XCTAssertEqual(merged.first?.updatedBy, "phone-b")
    }

    func testThisDevicesNewerValueIsKept() {
        let merged = InstallReportView.merged(
            local: [local(password: "typed-here", at: 300)],
            remote: [remote("single|Vaultwarden", password: "stale", at: 100)],
            deployment: deployment)
        XCTAssertEqual(merged.first?.password, "typed-here")
    }

    func testADeletedAccountDisappearsFromTheScreen() {
        let merged = InstallReportView.merged(
            local: [local(password: "old-here", at: 100)],
            remote: [remote("single|Vaultwarden", password: "", at: 200, deleted: true)],
            deployment: deployment)
        XCTAssertTrue(merged.isEmpty)
    }

    func testAnUneditedLocalValueDoesNotOverwriteTheServer() {
        let merged = InstallReportView.merged(
            local: [local(password: "from-report", at: 0)],
            remote: [remote("single|Vaultwarden", password: "recorded-elsewhere", at: 1)],
            deployment: deployment)
        XCTAssertEqual(merged.first?.password, "recorded-elsewhere")
    }

    // MARK: - Which refusal is which

    func testTheExpiredSessionMarkerIsRecognisedWhicheverErrorCarriesIt() {
        let rpc = AgentError.rpc(code: "unauthenticated",
                                 message: "session_expired: this device's session has run out")
        XCTAssertTrue(AccessVault.isSessionExpired(rpc))
        let wrapped = ServerControlError.commandFailed(
            command: "vault", exitCode: nil,
            stderr: "device_not_paired: this device is not paired with this server")
        XCTAssertTrue(AccessVault.isSessionExpired(wrapped))
    }

    func testAnOldClientRefusalIsNotReadAsAnExpiredSession() {
        let rpc = AgentError.rpc(code: "unauthenticated",
                                 message: "device_unidentified: this client did not say which device it is")
        XCTAssertTrue(AccessVault.isUnidentified(rpc))
        XCTAssertFalse(AccessVault.isSessionExpired(rpc))
    }

    func testAnOrdinaryFailureIsNeitherOfThem() {
        let rpc = AgentError.transport("the agent bridge did not start: Connection refused")
        XCTAssertFalse(AccessVault.isSessionExpired(rpc))
        XCTAssertFalse(AccessVault.isUnidentified(rpc))
    }

    // MARK: - What a refusal does to what this device holds

    @available(macOS 15.0, *)
    func testASignedOutDeviceLosesWhatItCached() {
        var fetched = AccessVault.Fetched()
        fetched.sessionExpired = true
        let outcome = InstallReportView.outcome(for: fetched)
        XCTAssertEqual(outcome, InstallReportView.SyncOutcome(state: .signedOut, clearsCache: true))
    }

    @available(macOS 15.0, *)
    func testADeviceTheServerCannotIdentifyKeepsWhatItCached() {
        var fetched = AccessVault.Fetched()
        fetched.unidentified = true
        let outcome = InstallReportView.outcome(for: fetched)
        XCTAssertEqual(outcome,
                       InstallReportView.SyncOutcome(state: .unidentified, clearsCache: false))
    }

    @available(macOS 15.0, *)
    func testAnOrdinaryFailureClearsNothing() {
        var fetched = AccessVault.Fetched()
        fetched.failure = "the agent bridge did not start"
        let outcome = InstallReportView.outcome(for: fetched)
        XCTAssertEqual(outcome,
                       InstallReportView.SyncOutcome(state: .failed("the agent bridge did not start"),
                                                     clearsCache: false))
    }

    @available(macOS 15.0, *)
    func testAServerThatAnsweredIsLeftToTheMerge() {
        var fetched = AccessVault.Fetched()
        fetched.reachedServer = true
        XCTAssertNil(InstallReportView.outcome(for: fetched))
    }

    // MARK: - Seeding the vault from the report

    func testASeededEntryCarriesNoTimestamp() {
        let entry = AccessVaultEntry.make(id: "single|Vaultwarden", host: "single",
                                          title: "Vaultwarden", website: nil,
                                          login: "admin", password: "from-the-report",
                                          token: "", updatedAt: nil, updatedBy: "agent")
        XCTAssertEqual(entry.updatedAt, 0)
        XCTAssertEqual(entry.updatedBy, "agent")
    }

    func testAnEditedEntryStillCarriesItsTime() {
        let when = Date(timeIntervalSince1970: 1_700_000)
        let entry = AccessVaultEntry.make(id: "single|Vaultwarden", host: "single",
                                          title: "Vaultwarden", website: nil,
                                          login: "admin", password: "typed-by-hand",
                                          token: "", updatedAt: when, updatedBy: "phone-a")
        XCTAssertEqual(entry.updatedAt, 1_700_000_000)
    }

    func testASeededEntryDoesNotWinAgainstAnEdit() {
        let seeded = AccessVaultEntry.make(id: "single|Vaultwarden", host: "single",
                                           title: "Vaultwarden", website: nil,
                                           login: "admin", password: "from-the-report",
                                           token: "", updatedAt: nil, updatedBy: "agent")
        let edited = remote("single|Vaultwarden", password: "typed-on-the-other-phone", at: 100)
        let winners = VaultMerge.resolved(local: [seeded], remote: [edited])
        XCTAssertEqual(winners.first?.password, "typed-on-the-other-phone")
    }

    func testASeededEntryIsKeptWhenTheServerHasNothing() {
        let seeded = AccessVaultEntry.make(id: "single|Vaultwarden", host: "single",
                                           title: "Vaultwarden", website: nil,
                                           login: "admin", password: "from-the-report",
                                           token: "", updatedAt: nil, updatedBy: "agent")
        let winners = VaultMerge.resolved(local: [seeded], remote: [])
        XCTAssertEqual(winners.first?.password, "from-the-report")
    }

    func testASeededEntryDoesNotUndoADeletion() {
        let seeded = AccessVaultEntry.make(id: "single|Vaultwarden", host: "single",
                                           title: "Vaultwarden", website: nil,
                                           login: "admin", password: "from-the-report",
                                           token: "", updatedAt: nil, updatedBy: "agent")
        let tombstone = remote("single|Vaultwarden", password: "", at: 100, deleted: true)
        let winners = VaultMerge.resolved(local: [seeded], remote: [tombstone])
        XCTAssertEqual(winners.first?.deleted, true)
    }

    // MARK: - What a Save actually sends

    func testASaveSendsBothTheEditsAndTheUntouchedReportValues() {
        var edited = local(password: "typed-by-hand", at: 0)
        edited.markLoadedValues()
        edited.password = "changed-just-now"
        let untouched = local(password: "from-the-report", at: 0)

        let out = InstallReportView.entriesToPush([edited, untouched],
                                                  at: Date(timeIntervalSince1970: 1_700_000),
                                                  writer: "phone-a")
        XCTAssertEqual(out.count, 2)
        let byPassword = Dictionary(uniqueKeysWithValues: out.map { ($0.password, $0) })
        XCTAssertEqual(byPassword["changed-just-now"]?.updatedAt, 1_700_000_000)
        XCTAssertEqual(byPassword["changed-just-now"]?.updatedBy, "phone-a")
        XCTAssertEqual(byPassword["from-the-report"]?.updatedAt, 0)
        XCTAssertEqual(byPassword["from-the-report"]?.updatedBy, "agent")
    }

    func testAnAccountWithNoCredentialIsNotSent() {
        var blank = local(password: "", at: 0)
        blank.login = ""
        blank.markLoadedValues()
        XCTAssertTrue(InstallReportView.entriesToPush([blank], at: Date(), writer: "phone-a").isEmpty)
    }
}
