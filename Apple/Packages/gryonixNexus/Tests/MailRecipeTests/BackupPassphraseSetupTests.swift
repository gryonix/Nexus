import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

final class BackupPassphraseSetupTests: XCTestCase {
    private let appKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMyDQB6mYEJGEwmaG7pwxsGYtqL9jGpLazp91J9hxAxk gryonixnexus-app"

    private func script(services: Set<ServiceID>, access: Bool = true) throws -> String {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                                 distribution: .debian)],
            dashboardAccess: access ? DashboardAccessInput(sshUser: "admin", appPublicKey: appKey) : nil,
            services: services,
            serviceSettings: ServiceSettings()
        )
        let bundle = try MailRecipe().generate(from: input)
        return try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-mail-server.sh" }?.contents)
    }

    /// A host with a secret store gets one
    func testAHostWithASecretStoreGeneratesAPassphrase() throws {
        let script = try script(services: [.vaultwarden])
        XCTAssertTrue(script.contains("if [ ! -s '\(BackupControlSections.passphrasePath)' ]; then"),
                      "the setup must create the passphrase the backup wrapper reads")
        XCTAssertTrue(script.contains("head -c 20 /dev/urandom"),
                      "generated on the SERVER, like every other credential here")
    }

    func testAHostWithNothingEncryptedGetsNoPassphrase() throws {
        let script = try script(services: [.jellyfin])
        XCTAssertFalse(script.contains("head -c 20 /dev/urandom"),
                       "bulk media is not encrypted by default, so there is nothing to unlock")
    }

    func testAnExistingPassphraseIsNeverReplaced() throws {
        let script = try script(services: [.vaultwarden])
        XCTAssertTrue(script.contains("if [ ! -s '\(BackupControlSections.passphrasePath)' ]; then"),
                      "re-running setup must not rotate a passphrase that already encrypts archives")
    }

    func testThePassphraseIsNeverWorldReadableEvenBriefly() throws {
        let script = try script(services: [.vaultwarden])
        XCTAssertTrue(script.contains("( umask 077 && head -c 20 /dev/urandom"),
                      "the umask has to be in force while the file is created, not applied afterwards")
    }

    func testTheReportNamesNoPassphraseWhereNoneIsWritten() throws {
        let script = try script(services: [.vaultwarden], access: false)
        XCTAssertFalse(script.contains("head -c 20 /dev/urandom"),
                       "no backup wrapper is installed without dashboard access")
        XCTAssertFalse(script.contains(L10nScripts.backupPassphraseLabel(.en)),
                       "the report must not ask the owner to keep a passphrase that is empty")
    }

    func testTheReportNamesThePassphraseWhereItIsWritten() throws {
        let script = try script(services: [.vaultwarden])
        XCTAssertTrue(script.contains("head -c 20 /dev/urandom"))
        XCTAssertTrue(script.contains(L10nScripts.backupPassphraseLabel(.en)))
    }

    func testTheGeneratedShapeMatchesTheAgents() throws {
        let script = try script(services: [.vaultwarden])
        XCTAssertTrue(script.contains("od -An -tx1"), "hex, like the agent's random_hex_20")
        XCTAssertTrue(script.contains("tr -d '[:space:]'"),
                      "no newline may survive into the file — the wrapper feeds it to gpg verbatim")
    }
}
