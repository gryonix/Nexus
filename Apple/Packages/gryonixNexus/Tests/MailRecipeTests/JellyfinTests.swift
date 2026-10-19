import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

/// Jellyfin, pinned over the GENERATED artifacts
final class JellyfinTests: XCTestCase {
    private func input(services: Set<ServiceID> = [.jellyfin]) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
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

    private var mediaPath: String { ServiceSettings().jellyfinMediaPath }

    /// The library is mounted read-only
    func testMediaLibraryIsMountedReadOnly() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("\(mediaPath):/media:ro"),
                      "the media library must be mounted read-only")
        XCTAssertFalse(script.contains("\(mediaPath):/media\n"),
                       "a writable media mount would let the web UI delete originals")
    }

    /// Uninstall never removes the library — not even with `--purge-data`
    func testUninstallNeverRemovesTheMediaLibrary() throws {
        let bundle = try MailRecipe().generate(from: input())
        let scripts = bundle.artifacts.map(\.contents).joined(separator: "\n")
        for line in scripts.split(separator: "\n") where line.contains("rm -rf") {
            XCTAssertFalse(line.contains(mediaPath),
                           "uninstall must never delete the media library: \(line)")
        }
    }

    func testBackupQuiescesTheContainerAndLeavesTheLibraryOut() throws {
        let script = try script(input())
        let body = try XCTUnwrap(script.range(of: "backup_jellyfin()").map {
            String(script[$0.lowerBound...].prefix(2000))
        }, "missing the generated jellyfin backup body")
        XCTAssertTrue(body.contains("gd_compose_stop 'jellyfin' 'jellyfin'"),
                      "the container must be stopped around the archive step")
        XCTAssertTrue(body.contains("gd_compose_start 'jellyfin' 'jellyfin'"),
                      "and started again on every path out")
        XCTAssertFalse(body.contains(mediaPath),
                       "the media library must not be part of the archive")
    }
}
