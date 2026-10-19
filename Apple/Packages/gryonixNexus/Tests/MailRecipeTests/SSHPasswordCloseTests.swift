import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

final class SSHPasswordCloseTests: XCTestCase {
    private func agentModule() throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        // <this file> → MailRecipeTests → Tests → gryonixNexus → Packages → Apple
        for _ in 0 ..< 6 { url.deleteLastPathComponent() }
        let source = url
            .appendingPathComponent("Server")
            .appendingPathComponent("gryonixnexusd")
            .appendingPathComponent("src")
            .appendingPathComponent("install")
            .appendingPathComponent("ssh_password.rs")
        let text = try String(contentsOf: source, encoding: .utf8)
        XCTAssertFalse(text.isEmpty, "found the agent module but it is empty: \(source.path)")
        return text
    }

    private func agentDropIn(in module: String) throws -> String {
        let start = try XCTUnwrap(module.range(of: "\"# Managed by gryonixNexus.\\n\\"),
                                  "the agent's drop_in() no longer starts with the managed marker")
        let tail = module[start.lowerBound...]
        let end = try XCTUnwrap(tail.range(of: "\"\n        .to_string()"),
                                "could not find the end of the agent's drop_in() literal")
        var body = String(tail[tail.index(after: start.lowerBound) ..< end.lowerBound])
        body = body.replacingOccurrences(of: "\\\n", with: "\n")
        body = body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.drop(while: { $0 == " " }) }
            .joined()
        return body.replacingOccurrences(of: "\\n", with: "\n")
    }

    func testTheTwoRoutesWriteTheSameDropIn() throws {
        let module = try agentModule()
        XCTAssertEqual(try agentDropIn(in: module), DashboardAccessSections.passwordAuthDropIn + "\n",
                       "the SSH install path and the agent would write different files")
    }

    func testTheTwoRoutesWriteTheSamePath() throws {
        let module = try agentModule()
        XCTAssertTrue(
            module.contains("pub const DROP_IN_PATH: &str = \"\(DashboardAccessSections.passwordAuthDropInPath)\";"),
            "the agent writes a different path than this generator does"
        )
    }

    func testTheDropInOutranksCloudInits() {
        let name = try! XCTUnwrap(DashboardAccessSections.passwordAuthDropInPath.split(separator: "/").last)
        XCTAssertLessThan(String(name), "50-cloud-init.conf")
        XCTAssertLessThan(String(name), "60-gryonixnexus-tunnel.conf")
        XCTAssertTrue(DashboardAccessSections.passwordAuthDropInPath.hasSuffix(".conf"),
                      "a file the include glob does not match configures nothing")
    }

    func testBothPasswordKeywordsAreClosed() {
        let directives = DashboardAccessSections.passwordAuthDropIn
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertEqual(directives, ["PasswordAuthentication no", "KbdInteractiveAuthentication no"])
    }

    /// The body is written from a single-quoted shell literal
    func testTheBodyCannotEndItsOwnShellLiteral() {
        XCTAssertFalse(DashboardAccessSections.passwordAuthDropIn.contains("'"))
    }

    private func access(createUser: Bool) -> DashboardAccessInput {
        DashboardAccessInput(
            sshUser: "admin",
            createUser: createUser,
            appPublicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeFakeFakeFakeFakeFakeFakeFakeFakeFakeFake gryonixnexus-app"
        )
    }

    func testExistingUserModeClosesNothing() {
        let script = DashboardAccessSections.passwordAuthClose(access(createUser: false), language: .en)
        XCTAssertEqual(script, ":")
        XCTAssertFalse(script.contains("PasswordAuthentication"))
    }

    func testTheGuardLooksForTheAppsOwnKey() {
        let script = DashboardAccessSections.passwordAuthClose(access(createUser: true), language: .en)
        XCTAssertTrue(script.contains("grep -qxF \"$SSHD_APP_KEY\" \"$SSHD_KEYS\""), script)
        XCTAssertFalse(script.contains("grep -q \"$SSHD_APP_KEY\""), "a substring match is not a key")
    }

    func testARejectedConfigurationIsRemovedAgainBeforeAnythingReloads() throws {
        let script = DashboardAccessSections.passwordAuthClose(access(createUser: true), language: .en)
        let test = try XCTUnwrap(script.range(of: "if sshd -t; then"))
        let removal = try XCTUnwrap(script.range(of: "rm -f '\(DashboardAccessSections.passwordAuthDropInPath)'"))
        let reload = try XCTUnwrap(script.range(of: "systemctl reload ssh"))
        XCTAssertLessThan(test.lowerBound, reload.lowerBound, "reloaded before the config was tested")
        XCTAssertLessThan(test.lowerBound, removal.lowerBound, "removed before the config was tested")
    }

    func testNoStepOfTheCloseCanAbortTheInstall() {
        let script = DashboardAccessSections.passwordAuthClose(access(createUser: true), language: .en)
        let staged = DashboardAccessSections.passwordAuthDropInPath + ".staged"
        let guarded = [
            "install -d -m 755 /etc/ssh/sshd_config.d || SSHD_WROTE=0",
            "' > '\(staged)' || SSHD_WROTE=0",
            "chmod 644 '\(staged)' 2>/dev/null || SSHD_WROTE=0",
            "mv '\(staged)' '\(DashboardAccessSections.passwordAuthDropInPath)' 2>/dev/null || SSHD_WROTE=0",
        ]
        for statement in guarded {
            XCTAssertTrue(script.contains(statement),
                          "under set -e an unguarded write aborts the whole install: \(statement)")
        }
        XCTAssertEqual(script.components(separatedBy: "|| SSHD_WROTE=0").count - 1, guarded.count)
    }

    func testAWriteThatDidNotLandIsReportedRatherThanAssumed() throws {
        let script = DashboardAccessSections.passwordAuthClose(access(createUser: true), language: .en)
        let landed = try XCTUnwrap(
            script.range(of: "[ ! -f '\(DashboardAccessSections.passwordAuthDropInPath)' ]"),
            "nothing checks that the file reached the disk"
        )
        let tested = try XCTUnwrap(script.range(of: "elif sshd -t; then"))
        XCTAssertLessThan(landed.lowerBound, tested.lowerBound,
                          "the check runs after the test that cannot fail")
        XCTAssertTrue(script.contains(L10nScripts.sshdPasswordCloseNotWritten(.en)), script)
    }

    func testTheHostItselfIsAskedWhetherPasswordsAreStillTaken() throws {
        let script = DashboardAccessSections.passwordAuthClose(access(createUser: true), language: .en)
        let reload = try XCTUnwrap(script.range(of: "systemctl reload ssh"))
        let asked = try XCTUnwrap(script.range(of: "sshd -T"),
                                  "sshd is never asked what it resolved")
        XCTAssertLessThan(reload.lowerBound, asked.lowerBound,
                          "asked before the reload, so it reads the OLD answer")
        let tail = String(script[asked.lowerBound...])
        XCTAssertTrue(tail.contains("passwordauthentication no"), tail)
        XCTAssertTrue(tail.contains("kbdinteractiveauthentication no"), tail)
        XCTAssertTrue(script.contains("tr 'A-Z' 'a-z'"), script)
        XCTAssertTrue(script.contains(L10nScripts.sshdPasswordCloseNotEffective(.en)), script)
    }

    func testSSHDIsReloadedAndNeverRestarted() {
        let script = DashboardAccessSections.passwordAuthClose(access(createUser: true), language: .en)
        XCTAssertFalse(script.contains("systemctl restart ssh"))
        XCTAssertFalse(script.contains("reboot"))
    }

    func testTheEraseTakesTheDropInOffBeforeStrippingTheKey() throws {
        let lines = DashboardAccessSections.passwordAuthCloseUninstallLines(indent: "  ").joined(separator: "\n")
        XCTAssertTrue(lines.contains("rm -f \(DashboardAccessSections.passwordAuthDropInPath)"), lines)
        XCTAssertTrue(lines.contains("systemctl reload ssh"), lines)

        for script in try singleHostAndRelayScripts() {
            let removal = try XCTUnwrap(
                script.range(of: "rm -f \(DashboardAccessSections.passwordAuthDropInPath)"),
                "the erase does not take the drop-in off at all"
            )
            let keyStrip = try XCTUnwrap(script.range(of: "grep -vxF \"$APP_KEY\""),
                                         "the erase no longer strips the app key")
            XCTAssertLessThan(removal.lowerBound, keyStrip.lowerBound,
                              "the key is stripped before password login comes back — neither way in")
        }
    }

    private func singleHostAndRelayScripts() throws -> [String] {
        let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeFakeFakeFakeFakeFakeFakeFakeFakeFakeFake gryonixnexus-app"
        let single = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost,
                                 publicAddress: .ipv4("203.0.113.4"),
                                 vpnAddress: nil,
                                 distribution: .debian)],
            dashboardAccess: DashboardAccessInput(sshUser: "admin", appPublicKey: key),
            services: [.vaultwarden]
        )
        let relay = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .vpsRelayWithHomeBackend,
            servers: [
                ServerNode(role: .vpsRelay,
                           publicAddress: .ipv4("203.0.113.4"),
                           vpnAddress: .ipv4("10.8.0.1"),
                           distribution: .debian),
                ServerNode(role: .homeBackend,
                           publicAddress: nil,
                           vpnAddress: .ipv4("10.8.0.2"),
                           distribution: .debian)
            ],
            dashboardAccess: DashboardAccessInput(sshUser: "admin", appPublicKey: key),
            services: [.vaultwarden]
        )
        var scripts: [String] = []
        for input in [single, relay] {
            let bundle = try MailRecipe(keyProvider: SSHPasswordFixedKeyProvider()).generate(from: input)
            scripts += bundle.artifacts.filter { $0.kind == .shellScript }.map(\.contents)
        }
        return scripts
    }
}

private final class SSHPasswordFixedKeyProvider: WireGuardKeyProvider, @unchecked Sendable {
    private var counter = 0
    func makeKeyPair(for slot: WireGuardKeySlot) throws -> WireGuardKeyPair {
        counter += 1
        return WireGuardKeyPair(privateKey: "PRIV\(counter)", publicKey: "PUB\(counter)")
    }
}
