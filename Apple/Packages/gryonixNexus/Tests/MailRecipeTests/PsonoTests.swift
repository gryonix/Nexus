import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

/// Psono, pinned over the GENERATED artifacts
final class PsonoTests: XCTestCase {
    private func input(services: Set<ServiceID> = [.psono],
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

    func testRegistrationIsClosedFromTheFirstWrite() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("ALLOW_REGISTRATION: False"))
        XCTAssertTrue(script.contains("\"allow_registration\": false"))
        XCTAssertTrue(script.contains("\"allow_custom_server\": false"),
                      "the client must not be able to point at a different backend")
    }

    func testTheServerKeypairComesFromTheImagesOwnGenerator() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("generateserverkeys.py > "),
                      "the keypair must come from the image's own generator, not from two unrelated random tokens")
        XCTAssertFalse(script.contains("PSONO_PRIVATE_KEY=__RANDOM__"),
                       "a keypair cannot be assembled from two independent random tokens")
        XCTAssertFalse(script.contains("PSONO_PUBLIC_KEY=__RANDOM__"))
    }

    func testTheDatabasePasswordIsThreadedFromEnvIntoSettingsYAML() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("PSONO_DB_PASSWORD=__RANDOM__"))
        XCTAssertTrue(script.contains("PS_DB_PASSWORD=\"$(grep '^PSONO_DB_PASSWORD=' /opt/psono/.env | cut -d= -f2-)\""))
        XCTAssertTrue(script.contains("'PASSWORD': '$PS_DB_PASSWORD'"),
                      "settings.yaml must carry the SAME password compose hands the db container")
    }

    func testTheAdministratorIsCreatedPromotedAndVerifiedOverTheCLI() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("manage.py createuser admin@example.com \"$PS_ADMIN_PASSWORD\" admin@example.com"))
        XCTAssertTrue(script.contains("manage.py promoteuser admin@example.com superuser"))
        XCTAssertTrue(script.contains("manage.py verifyuseremail admin@example.com"))
        XCTAssertTrue(script.contains("PSONO_ADMIN_PASSWORD=__RANDOM__"))
    }

    func testAdminCreationIsGatedOnAFreshInstallOnly() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("PS_FRESH=0"))
        XCTAssertTrue(script.contains("if [ ! -f /opt/psono/config/settings.yaml ]; then"))
        XCTAssertTrue(script.contains("PS_FRESH=1"))
        XCTAssertTrue(script.contains("if [ \"$PS_FRESH\" -eq 1 ]; then"),
                      "admin creation must be conditioned on the fresh-install flag")
    }

    func testMigrationsRunOnEveryPassNotOnlyFirstInstall() throws {
        let script = try script(input())
        let migrateIndex = try XCTUnwrap(script.range(of: "manage.py migrate"))
        let freshGateIndex = try XCTUnwrap(script.range(of: "if [ \"$PS_FRESH\" -eq 1 ]; then"))
        XCTAssertTrue(migrateIndex.lowerBound < freshGateIndex.lowerBound,
                      "migrate must run before the fresh-only admin-creation gate, not inside it")
    }

    func testTheDatabaseIsDumpedNeverArchived() throws {
        let script = try script(input())
        let body = try XCTUnwrap(script.range(of: "backup_psono()").map {
            String(script[$0.lowerBound...].prefix(1200))
        })
        XCTAssertTrue(body.contains("gd_dump_postgres 'psono' 'db' \"$work/gryonixnexus-db/psono.sql\""))
        XCTAssertFalse(body.contains("-C '/opt/psono' 'db'"),
                       "a tar of a live Postgres directory is a corrupt backup")
        XCTAssertTrue(body.contains("-C '/opt/psono' 'config'"),
                      "the config directory (settings.yaml, the keypair) is what the archive carries")
    }

    func testBackupEncryptsByDefault() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("psono) echo 1 ;;"))
    }

    func testItDoesNotTakeOverVaultwardensHostnameOrPort() throws {
        let script = try script(input(services: [.psono, .vaultwarden]))
        XCTAssertTrue(script.contains("psono.example.com {"), "Psono needs a site of its own")
        XCTAssertTrue(script.contains("vaultwarden.example.com {"),
                      "and Vaultwarden says which manager it is, the shelf now holding two")
        XCTAssertTrue(script.contains("\"127.0.0.1:8089:80\""))
        XCTAssertTrue(script.contains("reverse_proxy 127.0.0.1:8089"))
    }

    func testUninstallRemovesTheWholeInstallation() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("compose_down 'psono'"))
        XCTAssertTrue(script.contains("purge_path '/opt/psono'"))
        XCTAssertTrue(script.contains("purge_path '/opt/psono/config.pre-restore-'*"),
                      "a restore leaves the previous config aside; uninstall must take it too")
    }

    func testTheProvisioningStepIsNeitherFatalNorSilent() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("ps_why"), "a failed wait must be able to say why")
        XCTAssertTrue(script.contains("PS_DEADLINE=$(($(date +%s) + 300))"),
                      "a deadline, not a number of tries: each probe can burn its own timeout")
        let block = try XCTUnwrap(script.range(of: "ps_why() {").map {
            String(script[$0.lowerBound...].prefix(1800))
        })
        for line in block.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.hasPrefix("#"), text.contains("docker exec") else { continue }
            XCTAssertTrue(text.contains("timeout ") || text.hasSuffix("|| true"),
                          "an unguarded docker call here can hang or kill the install: \(text)")
        }
    }
}
