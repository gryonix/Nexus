import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

/// AdGuard Home, pinned over the GENERATED artifacts
final class AdGuardHomeTests: XCTestCase {
    private func input(services: Set<ServiceID> = [.adguardHome]) throws -> MailRecipeInput {
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

    func testPlainDNSIsPublishedOnLoopbackOnly() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("\"127.0.0.1:53:53/udp\""),
                      "UDP 53 must be bound to loopback")
        XCTAssertTrue(script.contains("\"127.0.0.1:53:53/tcp\""),
                      "TCP 53 must be bound to loopback")
        for line in script.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("- \"") || text.hasPrefix("- '") else { continue }
            guard text.contains(":53/") || text.hasSuffix(":53\"") else { continue }
            XCTAssertTrue(text.contains("127.0.0.1:"),
                          "a DNS port published on all addresses is an open resolver: \(text)")
        }
    }

    func testTheFirewallNeverOpensPort53() throws {
        let script = try script(input())
        for line in script.split(separator: "\n")
        where line.contains("dport") && line.contains("accept") {
            let ports = line.split(separator: "{").last.map(String.init) ?? String(line)
            XCTAssertFalse(ports.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .contains(where: { $0.hasPrefix("53") && ($0 == "53" || $0.hasPrefix("53 ")) }),
                           "port 53 must never be opened publicly: \(line)")
        }
    }

    func testTheSetupWizardIsClosedByProvisioningTheAdministrator() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("/control/install/configure"),
                      "the initial configuration call is what closes the wizard")
        XCTAssertTrue(script.contains("grep '^ADGUARD_ADMIN_PASSWORD=' /opt/adguardhome/.env"),
                      "the password must come from the server-generated .env")
        let configureLine = try XCTUnwrap(script.split(separator: "\n")
            .first { $0.contains("ag_api POST /control/install/configure") })
        XCTAssertFalse(configureLine.contains("$AG_PASSWORD"),
                       "the password must travel in the request file, not in the command line")
        XCTAssertTrue(script.contains("ag_why"),
                      "a failed call must be able to say why")
        let apiHelper = try XCTUnwrap(script.range(of: "ag_api() {").map {
            String(script[$0.lowerBound...].prefix(800))
        })
        for line in apiHelper.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.hasPrefix("#"), text.contains("curl ") else { continue }
            XCTAssertFalse(text.contains("curl -f"),
                           "-f throws away the body, which is the only explanation there is")
        }
    }

    func testBackupTakesTheConfigurationAndNotTheQueryLog() throws {
        let script = try script(input())
        let body = try XCTUnwrap(script.range(of: "backup_adguard_home()").map {
            String(script[$0.lowerBound...].prefix(1200))
        }, "missing the generated adguard-home backup body")
        XCTAssertTrue(body.contains("-C '/opt/adguardhome' 'conf'"),
                      "the configuration directory is what the archive carries")
        XCTAssertFalse(body.contains("/opt/adguardhome/work"),
                       "the query log and statistics must stay out of the archive")
    }

    func testTheImageIsPinnedAndCoveredByTheUpdateSpec() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("image: adguard/adguardhome:v0.107.78"),
                      "the compose file must carry the exact pinned tag")
        XCTAssertFalse(script.contains("adguard/adguardhome:latest"),
                       "a floating tag pulls whatever the registry currently serves")
        let context = ServiceContext(domain: "example.com", sshUser: "admin")
        XCTAssertEqual(AdGuardHomeService().updateSpec(context).images,
                       ["adguard/adguardhome:v0.107.78"],
                       "the update-ctl wrapper can only see an image the spec actually names")
    }

    func testUninstallRemovesTheWholeInstallation() throws {
        let script = try script(input())
        XCTAssertTrue(script.contains("compose_down 'adguardhome'"))
        XCTAssertTrue(script.contains("down --remove-orphans --volumes --rmi all"),
                      "tagged images are only reclaimed by --rmi all")
        XCTAssertTrue(script.contains("purge_path '/opt/adguardhome'"))
        XCTAssertTrue(script.contains("purge_path '/opt/adguardhome/conf.pre-restore-'*"),
                      "a restore leaves the previous configuration aside; uninstall must take it too")
    }
}
