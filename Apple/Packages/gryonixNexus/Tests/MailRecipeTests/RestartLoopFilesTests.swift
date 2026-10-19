import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

final class RestartLoopFilesTests: XCTestCase {
    private func script(_ services: Set<ServiceID>) throws -> String {
        let input = MailRecipeInput(
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
        let bundle = try MailRecipe().generate(from: input)
        return try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-mail-server.sh" },
                             "missing setup script").contents
    }

    func testTheMeshRecordsFileIsWrittenWithARealNewline() throws {
        let script = try script([.headscale])
        XCTAssertTrue(script.contains("printf '[]\\n'"),
                      "the empty records file must be written with a real newline")
        XCTAssertFalse(script.contains("printf '[]\\\\n'"),
                       "a doubled backslash here puts a literal backslash-n in the file and headscale never starts")
    }

    func testTheMeshRecordsFileIsRepairedWhereAnOlderBuildBrokeIt() throws {
        let script = try script([.headscale])
        XCTAssertTrue(script.contains("[ \"$(cat \"$HS_RECORDS\")\" = '[]\\n' ]"),
                      "a records file holding the literal backslash-n must be rewritten")
    }

    func testTheAutheliaImageIsPulledBeforeItsHashGeneratorRuns() throws {
        let script = try script([.authelia])
        let pull = try XCTUnwrap(script.range(of: "docker pull -q ghcr.io/authelia/authelia"),
                                 "the image must be pulled before the generator runs")
        let generate = try XCTUnwrap(script.range(of: "authelia crypto hash generate argon2 --random"),
                                     "missing the hash generator call")
        XCTAssertTrue(pull.lowerBound < generate.lowerBound,
                      "pulling after the run leaves docker's own Digest: line in the captured output")
    }

    func testTheAutheliaDigestIsReadAnchoredOnTheCryptDelimiter() throws {
        let script = try script([.authelia])
        XCTAssertTrue(script.contains("sed -n 's/^Digest: \\([$].*\\)$/\\1/p' | tail -n1"),
                      "the digest must be recognised by its leading $, and the last match taken")
        XCTAssertFalse(script.contains("sed -n 's/^Digest: //p' | head -n1"),
                       "the unanchored first match is docker's sha256 on any host without the image")
    }

    func testAUsersDatabaseThePortalCannotLoadIsRegenerated() throws {
        let script = try script([.authelia])
        XCTAssertTrue(script.contains("! grep -qF \"password: '\\$\" \"$AUTH_USERS\""),
                      "the step must re-run when the stored hash is not a hash")
    }

    func testTheMeshControlServerIsNotBehindTheVPNGuard() throws {
        let script = try script([.headscale])
        let site = try XCTUnwrap(script.range(of: "mesh.example.com {"), "missing the mesh site")
        let block = script[site.upperBound...].prefix(while: { $0 != "}" })
        XCTAssertFalse(block.contains("gryonixnexus-admin-guard"),
                       "behind the guard, a device away from home could never join the mesh")
        XCTAssertTrue(block.contains("reverse_proxy"), "the site must still proxy to headscale")
    }

    func testTheMeshControlServerIsNeverPutBehindSSO() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                                 distribution: .ubuntu)],
            dashboardAccess: DashboardAccessInput(
                sshUser: "admin",
                appPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMyDQB6mYEJGEwmaG7pwxsGYtqL9jGpLazp91J9hxAxk gryonixnexus-app"),
            services: [.headscale, .homepage, .authelia],
            serviceSettings: ServiceSettings(autheliaProtectedServices: [.headscale, .homepage])
        )
        let bundle = try MailRecipe().generate(from: input)
        let script = try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-mail-server.sh" }).contents
        XCTAssertFalse(script.contains("domain: 'mesh.example.com'"),
                       "a rule naming the control server means a device can never join")
        let site = try XCTUnwrap(script.range(of: "mesh.example.com {"), "missing the mesh site")
        let block = script[site.upperBound...].prefix(while: { $0 != "}" })
        XCTAssertFalse(block.contains("forward_auth"),
                       "the mesh site must not carry the SSO gate")
        XCTAssertTrue(script.contains("domain: 'start.example.com'"),
                      "the rest of the protected list must still be honoured")
    }

    func testAPortalWithNothingProtectedStillStarts() throws {
        // Authelia alone: nothing else installed, so nothing to protect.
        let text = try script([.authelia])
        XCTAssertTrue(text.contains("rules: []"),
                      "an empty rule LIST is still written, not a missing key")
        XCTAssertTrue(text.contains("default_policy: two_factor"),
                      "deny with no rules will not start")
        XCTAssertFalse(text.contains("default_policy: deny"),
                       "this configuration protects nothing, so deny would restart-loop")
    }

    func testProtectingSomethingRestoresTheDenyingDefault() throws {
        let text = try script([.authelia, .adguardHome])
        XCTAssertTrue(text.contains("default_policy: deny"), "with rules present, deny is legal and meant")
    }
}
