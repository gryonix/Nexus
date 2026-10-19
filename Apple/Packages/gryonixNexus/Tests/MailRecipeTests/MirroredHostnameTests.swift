import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

final class MirroredHostnameTests: XCTestCase {
    private func makeContext(services: Set<ServiceID>,
                             topology: Topology = .singleHost) throws -> MailContext {
        let servers: [ServerNode]
        switch topology {
        case .singleHost:
            servers = [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                                  distribution: .debian)]
        case .vpsRelayWithHomeBackend:
            servers = [
                ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"),
                           vpnAddress: .ipv4("10.8.0.1"), distribution: .debian),
                ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.8.0.2"),
                           distribution: .ubuntu)
            ]
        }
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            additionalDomains: [try Domain("example.org"), try Domain("example.net")],
            hostname: "mail.example.com",
            topology: topology,
            servers: servers,
            dashboardAccess: DashboardAccessInput(sshUser: "admin", appPublicKey: "ssh-ed25519 AAAAKEY app"),
            services: services,
            serviceSettings: ServiceSettings(wireguardVPNPort: 51821, xrayRealityPort: 8443),
            language: .en
        )
        return MailContext(input: input, renderer: StringTemplateRenderer())
    }

    /// Site headers as Caddy will see them: `a.example.com, a.example.org {`
    private func caddySiteHostnames(in script: String) -> [[String]] {
        var blocks: [[String]] = []
        var insideCaddyfile = false
        for line in script.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if text.hasPrefix("cat > /etc/caddy/Caddyfile") { insideCaddyfile = true; continue }
            if text == "EOF_CADDYFILE" { insideCaddyfile = false; continue }
            guard insideCaddyfile, text.hasSuffix(" {"), !(text.first?.isWhitespace ?? true) else { continue }
            blocks.append(String(text.dropLast(2))
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) })
        }
        return blocks
    }

    func testEveryCaddySiteHostnameHasAnAddressRecord() throws {
        for topology in Topology.allCases {
            let context = try makeContext(
                services: [.mailcow, .vaultwarden, .nextcloud, .immich, .amneziaWG],
                topology: topology)
            let recordedNames = Set(DNSRecordGenerator().records(in: context)
                .filter { $0.type == .a || $0.type == .aaaa }
                .map(\.name))
            let bundle = try MailRecipe().generate(from: context.input)
            let scripts = bundle.artifacts.filter { $0.kind == .shellScript }
            var checked = 0
            for script in scripts {
                for site in caddySiteHostnames(in: script.contents) {
                    for name in site {
                        XCTAssertTrue(recordedNames.contains(name),
                                      "\(topology): Caddy serves \(name) but no A/AAAA record is generated for it — ACME will fail for that name")
                        checked += 1
                    }
                }
            }
            XCTAssertGreaterThan(checked, 0, "\(topology): no Caddy sites found to check")
        }
    }

    func testMirroredMailHostGetsAddressRecords() throws {
        let context = try makeContext(services: [.mailcow])
        let names = Set(DNSRecordGenerator().records(in: context)
            .filter { $0.type == .a }.map(\.name))
        XCTAssertTrue(names.contains("mail.example.com"))
        XCTAssertTrue(names.contains("mail.example.org"))
        XCTAssertTrue(names.contains("mail.example.net"))
    }

    func testAddressRecordsAreNotDuplicated() throws {
        let context = try makeContext(services: [.mailcow, .vaultwarden, .nextcloud, .immich,
                                                 .forgejo, .gitlab])
        let names = DNSRecordGenerator().records(in: context)
            .filter { $0.type == .a }.map(\.name)
        XCTAssertEqual(names.count, Set(names).count, "duplicate A records: \(names)")
    }

    func testNextcloudTrustsEveryHostnameItsSiteServes() throws {
        let context = try makeContext(services: [.nextcloud])
        let script = try XCTUnwrap(try MailRecipe().generate(from: context.input)
            .artifacts.first { $0.kind == .shellScript }).contents
        let served = try XCTUnwrap(caddySiteHostnames(in: script)
            .first { $0.contains("files.example.com") })

        let trustedLine = try XCTUnwrap(script.split(separator: "\n")
            .first { $0.contains("NEXTCLOUD_TRUSTED_DOMAINS:") })
        for name in served {
            XCTAssertTrue(trustedLine.contains(name),
                          "NEXTCLOUD_TRUSTED_DOMAINS is missing \(name)")
            XCTAssertTrue(script.contains("trusted_domains") && script.contains("--value=\(name)"),
                          "no occ trusted_domains slot sets \(name)")
        }
        XCTAssertTrue(script.contains("config:system:delete overwritehost"), "a mirror is not sent to the main name")
        XCTAssertTrue(script.contains("overwrite.cli.url --value=https://files.example.com"))
    }

    func testSeafileTrustsEveryHostnameItsSiteServes() throws {
        let context = try makeContext(services: [.seafile])
        let script = try XCTUnwrap(try MailRecipe().generate(from: context.input)
            .artifacts.first { $0.kind == .shellScript }).contents
        let served = try XCTUnwrap(caddySiteHostnames(in: script)
            .first { $0.contains("files.example.com") })
        XCTAssertTrue(served.contains("files.example.org"))
        XCTAssertTrue(served.contains("files.example.net"))

        let trustedLine = try XCTUnwrap(script.split(separator: "\n")
            .first { $0.contains("CSRF_TRUSTED_ORIGINS = [") })
        for name in served {
            XCTAssertTrue(trustedLine.contains("'https://\(name)'"),
                          "CSRF_TRUSTED_ORIGINS is missing \(name) — that name answers sign-in with a CSRF error")
        }
        XCTAssertTrue(script.contains("SEAFILE_SERVER_HOSTNAME: files.example.com"))
        XCTAssertTrue(script.contains("SEAFILE_SERVER_PROTOCOL: https"),
                      "an http value here makes every download link a mixed-content block")
        for alias in ["files.example.org", "files.example.net"] {
            XCTAssertFalse(script.contains("SEAFILE_SERVER_HOSTNAME: \(alias)"),
                           "the canonical URL must not be split across aliases")
        }
    }

    func testForgejoKeepsOneCanonicalURLWhileItsSiteServesTheAliases() throws {
        let context = try makeContext(services: [.forgejo])
        let script = try XCTUnwrap(try MailRecipe().generate(from: context.input)
            .artifacts.first { $0.kind == .shellScript }).contents
        let served = try XCTUnwrap(caddySiteHostnames(in: script)
            .first { $0.contains("git.example.com") })
        XCTAssertTrue(served.contains("git.example.org"))
        XCTAssertTrue(served.contains("git.example.net"))

        XCTAssertTrue(script.contains("FORGEJO__server__ROOT_URL: https://git.example.com/"))
        XCTAssertTrue(script.contains("FORGEJO__server__DOMAIN: git.example.com"))
        for alias in ["git.example.org", "git.example.net"] {
            XCTAssertFalse(script.contains("ROOT_URL: https://\(alias)/"),
                           "the canonical URL must not be split across aliases")
        }
    }

    func testGitLabKeepsOneCanonicalURLWhileItsSiteServesTheAliases() throws {
        let context = try makeContext(services: [.gitlab])
        let script = try XCTUnwrap(try MailRecipe().generate(from: context.input)
            .artifacts.first { $0.kind == .shellScript }).contents
        let served = try XCTUnwrap(caddySiteHostnames(in: script)
            .first { $0.contains("git.example.com") })
        XCTAssertTrue(served.contains("git.example.org"))
        XCTAssertTrue(served.contains("git.example.net"))

        XCTAssertTrue(script.contains("external_url 'https://git.example.com'"))
        for alias in ["git.example.org", "git.example.net"] {
            XCTAssertFalse(script.contains("external_url 'https://\(alias)'"),
                           "the canonical URL must not be split across aliases")
        }
    }

    func testBothGitForgesCanBeInstalledTogether() throws {
        let context = try makeContext(services: [.forgejo, .gitlab])
        let script = try XCTUnwrap(try MailRecipe().generate(from: context.input)
            .artifacts.first { $0.kind == .shellScript }).contents
        // Two forges, so neither keeps the plain `git` name.
        XCTAssertNotNil(caddySiteHostnames(in: script).first { $0.contains("forgejo.example.com") })
        XCTAssertNotNil(caddySiteHostnames(in: script).first { $0.contains("gitlab.example.com") })
        let openTCP = try XCTUnwrap(script.split(separator: "\n")
            .first { $0.contains("tcp dport {") && $0.contains("HTTP for ACME") })
        XCTAssertTrue(openTCP.contains("2222"))
        XCTAssertTrue(openTCP.contains("2223"))
    }

    func testUninstallRemovesTheAliasedCaddyBlock() throws {
        let context = try makeContext(services: [.nextcloud, .vaultwarden])
        let script = try XCTUnwrap(try MailRecipe().generate(from: context.input)
            .artifacts.first { $0.kind == .shellScript }).contents
        for site in caddySiteHostnames(in: script) {
            let header = site.joined(separator: ", ")
            XCTAssertTrue(script.contains("remove_caddy_site '\(header)'"),
                          "uninstall does not remove the Caddy block for \(header)")
        }
    }
}
