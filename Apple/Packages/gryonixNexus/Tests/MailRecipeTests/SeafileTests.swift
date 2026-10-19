import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

/// Seafile, pinned over the GENERATED artifacts
final class SeafileTests: XCTestCase {
    private func input(services: Set<ServiceID> = [.seafile],
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

    func testTheAdministratorIsOursAndNeverUpstreamsDocumentedDefault() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("INIT_SEAFILE_ADMIN_EMAIL: admin@example.com"),
                      "Seafile rejects a login that is not an email address")
        XCTAssertTrue(script.contains("INIT_SEAFILE_ADMIN_PASSWORD: ${SEAFILE_ADMIN_PASSWORD}"),
                      "the password must come from the .env, not from the artifact")
        XCTAssertTrue(script.contains("SEAFILE_ADMIN_PASSWORD=__RANDOM__"),
                      "the password must be generated on the server")
        let effective = effectiveLines(script)
        XCTAssertFalse(effective.contains("me@example.com"))
        XCTAssertFalse(effective.contains("asecret"))
    }

    func testTheSigningKeyIsGeneratedOnTheServer() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("JWT_PRIVATE_KEY: ${SEAFILE_JWT_PRIVATE_KEY}"))
        XCTAssertTrue(script.contains("SEAFILE_JWT_PRIVATE_KEY=__RANDOM__"))
    }

    func testTheCacheCompanionMatchesTheVersionsOwnDefault() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("CACHE_PROVIDER: redis"))
        XCTAssertTrue(script.contains("REDIS_HOST: redis"))
        let compose = try XCTUnwrap(script.range(of: "cat > /opt/seafile/docker-compose.yml").map {
            String(script[$0.lowerBound...].prefix(3000))
        })
        XCTAssertTrue(compose.contains("\n  redis:\n"), "no service is named redis")
        XCTAssertFalse(compose.contains("memcached"),
                       "memcached was the version 12 default and answers nothing here")
    }

    func testDocumentEditingIsOffBecauseItsServerIsNotInstalled() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("ENABLE_SEADOC: \"false\""))
        XCTAssertFalse(effectiveLines(script).contains("sdoc-server"),
                       "nothing may point at a document server this install does not run")
    }

    /// All THREE databases are dumped, by name
    func testAllThreeDatabasesAreDumpedByNameAndNeverArchived() throws {
        let script = try script(input())
        let body = try XCTUnwrap(script.range(of: "backup_seafile()").map {
            String(script[$0.lowerBound...].prefix(2000))
        }, "missing the generated seafile backup body")
        for database in ["ccnet_db", "seafile_db", "seahub_db"] {
            XCTAssertTrue(body.contains("gd_dump_mysql 'seafile' 'db' "
                                        + "\"$work/gryonixnexus-db/\(database).sql\" '\(database)'"),
                          "\(database) is not dumped by name")
        }
        XCTAssertTrue(body.contains("-C '/opt/seafile' 'data'"),
                      "the /shared mount is what the archive carries")
        XCTAssertFalse(body.contains("'/opt/seafile' 'db'"),
                       "a tar of a live MariaDB directory is a corrupt backup")
        let restore = try XCTUnwrap(script.range(of: "restore_seafile()").map {
            String(script[$0.lowerBound...].prefix(3000))
        }, "missing the generated seafile restore body")
        for database in ["ccnet_db", "seafile_db", "seahub_db"] {
            XCTAssertTrue(restore.contains("gd_load_mysql 'seafile' 'db' "
                                           + "\"$stage/gryonixnexus-db/\(database).sql\" '\(database)'"),
                          "\(database) is not loaded back by name")
        }
    }

    func testASingleDatabaseServiceStillUsesItsContainersOwnName() throws {
        let script = try script(input(services: [.seafile, .nextcloud]))
        let body = try XCTUnwrap(script.range(of: "backup_nextcloud()").map {
            String(script[$0.lowerBound...].prefix(1400))
        })
        XCTAssertTrue(body.contains("gd_dump_mysql 'nextcloud' 'db' "
                                    + "\"$work/gryonixnexus-db/nextcloud.sql\" || rc=1"),
                      "a one-database service must keep its unnamed call")
        XCTAssertTrue(script.contains("\"${1:-$MYSQL_DATABASE}\""),
                      "the helper must still fall back to the container's own variable")
    }

    func testTheServerIsQuiescedForTheArchiveButTheDatabaseStaysUp() throws {
        let script = try script(input())
        let body = try XCTUnwrap(script.range(of: "backup_seafile()").map {
            String(script[$0.lowerBound...].prefix(2000))
        })
        XCTAssertTrue(body.contains("gd_compose_stop 'seafile' 'seafile'"))
        XCTAssertFalse(body.contains("gd_compose_stop 'seafile' 'seafile' 'db'"),
                       "the database has to stay up for its own dump")
        XCTAssertTrue(body.contains("gd_compose_start 'seafile' 'seafile'"),
                      "a backup that leaves the service down is an outage")
    }

    func testTheProvisioningStepIsNeitherFatalNorSilent() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("sf_why"),
                      "a failed wait must be able to say why")
        XCTAssertTrue(script.contains("SF_DEADLINE=$(($(date +%s) + 600))"),
                      "a deadline, not a number of tries: each probe can burn its own timeout")
        let block = try XCTUnwrap(script.range(of: "sf_why() {").map {
            String(script[$0.lowerBound...].prefix(1600))
        })
        for line in block.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.hasPrefix("#"), text.contains("docker compose") else { continue }
            XCTAssertTrue(text.contains("timeout ") || text.hasSuffix("|| true"),
                          "an unguarded docker call here can hang or kill the install: \(text)")
        }
    }

    func testTheTrustedOriginListIsReappliedRatherThanAppended() throws {
        let script = try script(input(aliases: ["example.org"]))
        XCTAssertTrue(script.contains("sed -i '/^CSRF_TRUSTED_ORIGINS = /d'"),
                      "without the delete a re-run leaves a stale list above the new one")
        XCTAssertTrue(script.contains(
            "CSRF_TRUSTED_ORIGINS = ['https://files.example.com', 'https://files.example.org']"))
        XCTAssertTrue(script.contains("docker compose -p seafile restart seafile"))
    }

    func testItDoesNotTakeOverNextcloudsHostnameOrPort() throws {
        let script = try script(input(services: [.seafile, .nextcloud],
                                      aliases: ["example.org"]))
        XCTAssertTrue(script.contains("seafile.example.com, seafile.example.org {"),
                      "Seafile needs a site of its own")
        XCTAssertTrue(script.contains("nextcloud.example.com, nextcloud.example.org {"),
                      "and Nextcloud says which one it is, the shelf now holding two")
        XCTAssertTrue(script.contains("\"127.0.0.1:8088:80\""))
        XCTAssertTrue(script.contains("reverse_proxy 127.0.0.1:8088"))
        XCTAssertTrue(script.contains("reverse_proxy 127.0.0.1:8081"))
    }

    func testUninstallRemovesTheWholeInstallation() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("compose_down 'seafile'"))
        XCTAssertTrue(script.contains("purge_path '/opt/seafile'"))
        XCTAssertTrue(script.contains("purge_path '/opt/seafile/data.pre-restore-'*"),
                      "a restore leaves the previous data aside; uninstall must take it too")
    }
}
