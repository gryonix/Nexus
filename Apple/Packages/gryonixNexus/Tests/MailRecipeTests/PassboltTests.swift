import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

/// Passbolt, pinned over the GENERATED artifacts
final class PassboltTests: XCTestCase {
    private func input(services: Set<ServiceID> = [.passbolt],
                       aliases: [String] = []) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            additionalDomains: try aliases.map { try Domain($0) },
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                                 distribution: .ubuntu)],
            dashboardAccess: DashboardAccessInput(
                sshUser: "admin",
                appPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMyDQB6mYEJGEwmaG7pwxsGYtqL9jGpLazp91J9hxAxk gryonixnexus-app"),
            services: services
        )
    }

    private func script(_ input: MailRecipeInput) throws -> String {
        let bundle = try MailRecipe().generate(from: input)
        return try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-mail-server.sh" },
                             "missing setup script").contents
    }

    /// The script with its comment lines dropped
    private func effectiveLines(_ script: String) -> String {
        script.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
    }

    func testThereIsNoAdminPasswordBecauseTheArchitectureHasNoUseForOne() throws {
        let script = try script(input())
        XCTAssertFalse(script.contains("PASSBOLT_ADMIN_PASSWORD"),
                       "Passbolt's admin identity is a GPG keypair generated in the browser, never a password the server can set")
        XCTAssertTrue(script.contains("PASSBOLT_DB_ROOT_PASSWORD=__RANDOM__"))
        XCTAssertTrue(script.contains("PASSBOLT_DB_PASSWORD=__RANDOM__"))
    }

    func testTheDatabaseRootPasswordIsSetExplicitlyUnlikeUpstreamsOwnReference() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("MYSQL_ROOT_PASSWORD: ${PASSBOLT_DB_ROOT_PASSWORD}"))
        XCTAssertFalse(effectiveLines(script).contains("MYSQL_RANDOM_ROOT_PASSWORD"),
                       "a randomized-and-discarded root password makes this service's own backups impossible")
    }

    func testAdminInvitationIsGatedOnTheServersOwnFreshnessSignal() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("PB_FRESH=0"))
        XCTAssertTrue(script.contains("[ -f /opt/passbolt/secrets/gpg/serverkey_private.asc ] || PB_FRESH=1"))
        XCTAssertTrue(script.contains("if [ \"$PB_FRESH\" -eq 1 ]; then"))
    }

    func testTheAdministratorIsRegisteredAndTheSetupURLIsCaptured() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains(
            "cake passbolt register_user -u 'admin@example.com' -f 'Admin' -l 'Admin' -r admin"))
        XCTAssertTrue(script.contains("grep -oE 'https?://[^[:space:]]+'"),
                      "the one-time setup URL must be pulled out of the command's own output")
        XCTAssertTrue(script.contains("> /opt/passbolt/.registration-url"))
        XCTAssertTrue(script.contains("chmod 600 /opt/passbolt/.registration-url"))
    }

    func testAStaleSetupLinkIsClearedBeforeEachFreshAttempt() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("rm -f /opt/passbolt/.registration-url"))
    }

    func testTheReportPrintsTheURLOrAFallbackNoteNeverAPassword() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("if [ -s /opt/passbolt/.registration-url ]; then"))
        XCTAssertTrue(script.contains("cat /opt/passbolt/.registration-url"))
        XCTAssertFalse(script.contains("passwordGeneratedOnServerLabel"),
                       "this service must not reuse the password-report label every other service uses")
    }

    func testTheGPGAndJWTTreesAreArchivedTogetherAndTheDatabaseIsDumpedNeverTarred() throws {
        let script = try script(input())
        let body = try XCTUnwrap(script.range(of: "backup_passbolt()").map {
            String(script[$0.lowerBound...].prefix(1200))
        })
        XCTAssertTrue(body.contains("-C '/opt/passbolt' 'secrets'"),
                      "gpg/ and jwt/ live together under secrets/ so one archive carries both")
        XCTAssertTrue(body.contains("gd_dump_mysql 'passbolt' 'db' \"$work/gryonixnexus-db/passbolt.sql\""))
        XCTAssertFalse(body.contains("-C '/opt/passbolt' 'db'"),
                       "a tar of a live MariaDB directory is a corrupt backup")
    }

    func testTheSecretDirectoriesAreWritableByTheContainersOwnUser() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("install -d -m 770 -o root -g 33 /opt/passbolt/secrets/gpg"),
                      "the server writes its generated GPG keypair here as www-data")
        XCTAssertTrue(script.contains("install -d -m 750 -o root -g 33 /opt/passbolt/secrets/jwt"),
                      "the JWT signing keys land here under the same ownership")
        XCTAssertFalse(script.contains("/opt/passbolt/secrets/gpg /opt/passbolt/secrets/jwt"),
                       "these two must not be folded back into the 755 root:root install -d")
    }

    func testBackupEncryptsByDefault() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("passbolt) echo 1 ;;"))
    }

    func testOnlyPort80IsPublishedNeverThePassboltsOwnTLSPort() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("\"127.0.0.1:8090:80\""))
        XCTAssertFalse(script.contains(":443:443"))
        XCTAssertTrue(script.contains("reverse_proxy 127.0.0.1:8090"))
    }

    func testItDoesNotTakeOverVaultwardenOrPsonosHostnameOrPort() throws {
        let script = try script(input(services: [.passbolt, .vaultwarden, .psono]))
        XCTAssertTrue(script.contains("passbolt.example.com {"), "Passbolt needs a site of its own")
        XCTAssertTrue(script.contains("vaultwarden.example.com {"))
        XCTAssertTrue(script.contains("psono.example.com {"))
    }

    func testUninstallRemovesTheWholeInstallation() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("compose_down 'passbolt'"))
        XCTAssertTrue(script.contains("purge_path '/opt/passbolt'"))
        XCTAssertTrue(script.contains("purge_path '/opt/passbolt/secrets.pre-restore-'*"),
                      "a restore leaves the previous secrets aside; uninstall must take it too")
    }

    func testTheProvisioningStepIsNeitherFatalNorSilent() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("pb_why"), "a failed wait must be able to say why")
        XCTAssertTrue(script.contains("PB_DEADLINE=$(($(date +%s) + 300))"),
                      "a deadline, not a number of tries: each probe can burn its own timeout")
        let block = try XCTUnwrap(script.range(of: "pb_why() {").map {
            String(script[$0.lowerBound...].prefix(2000))
        })
        for line in block.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.hasPrefix("#"), text.contains("docker exec") else { continue }
            XCTAssertTrue(text.contains("timeout ") || text.hasSuffix("|| true") || text.contains("if pb_exec"),
                          "an unguarded docker call here can hang or kill the install: \(text)")
        }
    }
}
