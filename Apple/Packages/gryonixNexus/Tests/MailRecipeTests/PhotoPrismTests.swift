import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

/// PhotoPrism, pinned over the GENERATED artifacts
final class PhotoPrismTests: XCTestCase {
    private func input(services: Set<ServiceID> = [.photoprism],
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

    func testTheAdministratorComesFromTheServerGeneratedEnvironment() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("PHOTOPRISM_ADMIN_USER: admin"))
        XCTAssertTrue(script.contains("PHOTOPRISM_ADMIN_PASSWORD: ${PHOTOPRISM_ADMIN_PASSWORD}"),
                      "the password must come from the .env, not from the artifact")
        XCTAssertTrue(script.contains("PHOTOPRISM_ADMIN_PASSWORD=__RANDOM__"),
                      "the password must be generated on the server")
        XCTAssertTrue(script.contains("PHOTOPRISM_AUTH_MODE: \"password\""),
                      "public mode would publish the whole library")
    }

    func testTLSIsLeftToTheProxy() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("PHOTOPRISM_DISABLE_TLS: \"true\""))
        XCTAssertTrue(script.contains("PHOTOPRISM_DEFAULT_TLS: \"false\""))
        XCTAssertTrue(script.contains("\"127.0.0.1:2342:2342\""),
                      "the web UI belongs on loopback behind Caddy")
    }

    func testTheDatabaseIsDumpedThroughItsOwnClientAndNeverArchived() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}"),
                      "the dump reads the root password from the container's own environment")
        XCTAssertTrue(script.contains("MYSQL_DATABASE: photoprism"),
                      "the dump reads the database name from the container's own environment")
        let body = try XCTUnwrap(script.range(of: "backup_photoprism()").map {
            String(script[$0.lowerBound...].prefix(1400))
        }, "missing the generated photoprism backup body")
        XCTAssertTrue(body.contains("gd_dump_mysql 'photoprism' 'mariadb'"))
        XCTAssertTrue(body.contains("-C '/opt/photoprism' 'originals'"),
                      "the pictures are what the archive carries")
        XCTAssertFalse(body.contains("'/opt/photoprism' 'db'"),
                       "a tar of a live MariaDB directory is a corrupt backup")
    }

    func testItDoesNotTakeOverImmichsHostname() throws {
        let script = try script(input(services: [.photoprism, .immich],
                                      aliases: ["example.org"]))
        XCTAssertTrue(script.contains("photoprism.example.com, photoprism.example.org {"),
                      "PhotoPrism needs a site of its own")
        XCTAssertTrue(script.contains("immich.example.com, immich.example.org {"),
                      "and Immich gives up the plain name, the shelf now holding two")
        XCTAssertTrue(script.contains("PHOTOPRISM_SITE_URL: \"https://photoprism.example.com/\""),
                      "the canonical URL stays single-valued at the primary domain")
        for alias in ["photoprism.example.org"] {
            XCTAssertFalse(script.contains("PHOTOPRISM_SITE_URL: \"https://\(alias)/\""),
                           "the canonical URL must not be split across aliases")
        }
    }

    func testBothImagesArePinnedAndCoveredByTheUpdateSpec() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("image: photoprism/photoprism:260728"),
                      "the compose file must carry the exact pinned application tag")
        XCTAssertTrue(script.contains("image: mariadb:11"),
                      "the compose file must carry the exact pinned database tag")
        XCTAssertFalse(script.contains("photoprism/photoprism:latest"))
        XCTAssertFalse(script.contains("mariadb:latest"),
                       "a floating tag on the database companion is as dangerous as one on the app")
        let context = ServiceContext(domain: "example.com", sshUser: "admin")
        XCTAssertEqual(Set(PhotoPrismService().updateSpec(context).images),
                       Set(["photoprism/photoprism:260728", "mariadb:11"]),
                       "the update-ctl wrapper can only see an image the spec actually names")
    }

    func testUninstallPurgeTakesTheWholeDirectoryIncludingTheOriginalsLibrary() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("compose_down 'photoprism'"))
        XCTAssertTrue(script.contains("purge_path '/opt/photoprism'"),
                      "this line also removes /opt/photoprism/originals, the owner's own library")
        XCTAssertTrue(script.contains("purge_path '/opt/photoprism/originals.pre-restore-'*"),
                      "a restore leaves the previous originals aside; uninstall must take it too")
    }
}
