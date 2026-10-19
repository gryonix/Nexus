import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

final class LocalOnlyDeploymentTests: XCTestCase {
    private func localOnlyInput(domain: String = "home.local",
                                services: Set<ServiceID> = [.vaultwarden]) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain(localOnly: domain),
            hostname: "mail.\(domain)",
            topology: .singleHost,
            scope: .localOnly,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("192.168.1.50"), distribution: .debian)],
            services: services
        )
    }

    private func publicInput(services: Set<ServiceID> = [.vaultwarden]) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"), distribution: .debian)],
            services: services
        )
    }

    private func artifact(_ name: String, in bundle: GeneratedBundle) -> Artifact? {
        bundle.artifacts.first { $0.fileName == name }
    }

    // MARK: - A. No DNS artifacts

    func testLocalOnlyProducesNoDNSArtifacts() throws {
        let bundle = try MailRecipe().generate(from: try localOnlyInput())
        XCTAssertTrue(bundle.artifacts.allSatisfy { $0.kind != .dnsRecord },
                      "a local-only bundle must carry no DNS-record artifact of any kind")
        XCTAssertNil(artifact("dns-records.txt", in: bundle))
        XCTAssertNil(artifact("home.local-dns-zone.txt", in: bundle))
        XCTAssertNil(artifact("home.local-dns-records.csv", in: bundle))
        XCTAssertEqual(Set(bundle.artifacts.map(\.fileName)), ["setup-mail-server.sh"])
    }

    func testPublicScopeStillProducesDNSArtifacts() throws {
        let bundle = try MailRecipe().generate(from: try publicInput())
        XCTAssertNotNil(artifact("dns-records.txt", in: bundle))
        XCTAssertNotNil(artifact("example.com-dns-zone.txt", in: bundle))
        XCTAssertNotNil(artifact("example.com-dns-records.csv", in: bundle))
    }

    func testLocalOnlyRecordsListIsEmpty() throws {
        let context = MailContext(input: try localOnlyInput(), renderer: StringTemplateRenderer())
        XCTAssertTrue(DNSRecordGenerator().records(in: context).isEmpty)
    }

    func testLocalOnlyOmitsDNSNotes() throws {
        let bundle = try MailRecipe().generate(from: try localOnlyInput())
        XCTAssertFalse(bundle.notes.contains { $0.contains("dns-records.txt") },
                       "no note should point at a file the bundle does not contain")
    }

    func testLocalOnlyReportOmitsDNSAndPTRReminders() throws {
        let bundle = try MailRecipe().generate(from: try localOnlyInput())
        let script = try XCTUnwrap(artifact("setup-mail-server.sh", in: bundle)).contents
        XCTAssertFalse(script.contains("dns-records.txt"),
                       "local-only has no DNS artifact — the report must not point at one")
        XCTAssertFalse(script.contains("PTR at your provider"),
                       "local-only has no public address — a PTR reminder makes no sense")
    }

    func testPublicScopeStillPrintsDNSAndPTRReminders() throws {
        let bundle = try MailRecipe().generate(from: try publicInput())
        let script = try XCTUnwrap(artifact("setup-mail-server.sh", in: bundle)).contents
        XCTAssertTrue(script.contains("dns-records.txt"))
        XCTAssertTrue(script.contains("PTR at your provider"))
    }

    // MARK: - B. Caddy `tls internal`

    func testLocalOnlyCaddySiteUsesTLSInternal() throws {
        let bundle = try MailRecipe().generate(from: try localOnlyInput(services: [.vaultwarden]))
        let script = try XCTUnwrap(artifact("setup-mail-server.sh", in: bundle)).contents
        XCTAssertTrue(script.contains("""
        vault.home.local {
            tls internal
            reverse_proxy 127.0.0.1:
        """) || script.contains("tls internal"),
                      "the site block must self-sign instead of asking Caddy for an ACME certificate")
        // Precise placement: same site block, same indentation as reverse_proxy.
        let lines = script.components(separatedBy: "\n")
        guard let siteLine = lines.firstIndex(where: { $0.contains("vault.home.local {") }) else {
            return XCTFail("vaultwarden site block not found")
        }
        XCTAssertEqual(lines[siteLine + 1].trimmingCharacters(in: .whitespaces),
                       "# gryonixnexus: vaultwarden")
        XCTAssertEqual(lines[siteLine + 2].trimmingCharacters(in: .whitespaces), "tls internal")
    }

    func testPublicScopeCaddySiteDoesNotUseTLSInternal() throws {
        let bundle = try MailRecipe().generate(from: try publicInput(services: [.vaultwarden]))
        let script = try XCTUnwrap(artifact("setup-mail-server.sh", in: bundle)).contents
        XCTAssertFalse(script.contains("tls internal"),
                       "a public-internet deployment keeps automatic ACME — no self-signed directive")
    }

    func testLocalOnlyAdminGuardedSiteAlsoUsesTLSInternal() throws {
        let line = ServiceInfraSections.caddySite(owner: "vpn", hostname: "vpn.home.local",
                                                  upstreamPort: 8080,
                                                  adminGuard: true, tlsInternal: true)
        XCTAssertTrue(line.contains("tls internal"))
        XCTAssertEqual(line.split(separator: "\n").dropFirst().first?.trimmingCharacters(in: .whitespaces),
                       "# gryonixnexus: vpn")
        let tlsIndex = try XCTUnwrap(line.range(of: "tls internal"))
        let importIndex = try XCTUnwrap(line.range(of: "import"))
        XCTAssertTrue(tlsIndex.lowerBound < importIndex.lowerBound)
    }

    // MARK: - C. Mail engines excluded

    func testEveryMailEngineRequiresAPublicDomain() {
        XCTAssertFalse(ServiceRegistry.mailEngines.isEmpty, "the catalog is expected to carry mail engines")
        for engine in ServiceRegistry.mailEngines {
            XCTAssertTrue(engine.requiresPublicDomain, "\(engine.displayName) must require a public domain")
        }
    }

    /// Services with no public-domain need (vaultwarden here) are unaffected
    func testOrdinaryServiceDoesNotRequireAPublicDomain() {
        XCTAssertFalse(VaultwardenService().requiresPublicDomain)
    }

    func testGenerationRejectsMailEnginePlusLocalOnly() throws {
        for engine: ServiceID in [.mailcow, .mailu, .dockerMailserver] {
            let input = try localOnlyInput(services: [engine])
            XCTAssertThrowsError(try MailRecipe().generate(from: input)) { error in
                guard case ValidationError.inconsistentTopology(let reason) = error else {
                    return XCTFail("expected .inconsistentTopology for \(engine), got \(error)")
                }
                XCTAssertFalse(reason.isEmpty)
            }
        }
    }

    func testSameMailSelectionIsValidUnderPublicScope() throws {
        XCTAssertNoThrow(try MailRecipe().generate(from: try publicInput(services: [.mailcow])))
    }

    func testLocalOnlyWithoutMailValidates() throws {
        XCTAssertNoThrow(try MailRecipe().generate(from: try localOnlyInput(services: [.vaultwarden, .nextcloud])))
    }

    func testGenerationRejectsVPNPlusLocalOnly() throws {
        for vpnService: ServiceID in [.wireguardVPN, .amneziaWG, .shadowsocks, .xrayReality, .openVPN, .vpnPanel] {
            let input = try localOnlyInput(services: [.vaultwarden, vpnService])
            XCTAssertThrowsError(try MailRecipe().generate(from: input)) { error in
                guard case ValidationError.inconsistentTopology(let reason) = error else {
                    return XCTFail("expected .inconsistentTopology for \(vpnService), got \(error)")
                }
                XCTAssertFalse(reason.isEmpty)
            }
        }
    }

    /// The same VPN selection is perfectly valid under `.publicInternet`
    func testSameVPNSelectionIsValidUnderPublicScope() throws {
        XCTAssertNoThrow(try MailRecipe().generate(from: try publicInput(services: [.wireguardVPN, .vpnPanel])))
    }

    func testLocalOnlyAcceptsALANIPAsItsAddress() throws {
        let bundle = try MailRecipe().generate(from: try localOnlyInput(domain: "192.168.1.50"))
        let script = try XCTUnwrap(artifact("setup-mail-server.sh", in: bundle)).contents
        XCTAssertTrue(script.contains("vault.192.168.1.50 {"),
                      "the composed default hostname (prefix + the IP address) must appear as a real Caddy site name")
        let lines = script.components(separatedBy: "\n")
        guard let siteLine = lines.firstIndex(where: { $0.contains("vault.192.168.1.50 {") }) else {
            return XCTFail("vaultwarden site block not found")
        }
        XCTAssertEqual(lines[siteLine + 1].trimmingCharacters(in: .whitespaces),
                       "# gryonixnexus: vaultwarden")
        XCTAssertEqual(lines[siteLine + 2].trimmingCharacters(in: .whitespaces), "tls internal")
    }

    func testLocalOnlyStillAcceptsALocalStyleHostname() throws {
        XCTAssertNoThrow(try Domain(localOnly: "server.local"))
        let bundle = try MailRecipe().generate(from: try localOnlyInput(domain: "server.local"))
        let script = try XCTUnwrap(artifact("setup-mail-server.sh", in: bundle)).contents
        XCTAssertTrue(script.contains("vault.server.local {"))
    }

    func testPublicInternetStillRejectsARawIP() {
        XCTAssertThrowsError(try Domain("192.168.1.50"))
    }

    func testLocalOnlyRejectsGarbage() {
        XCTAssertThrowsError(try Domain(localOnly: "not a domain or an ip!!"))
    }

    // MARK: - G. Honest gaps: SetupScripts / NftablesConfig are NOT wired yet

    func testDNSCheckGateStillFollowsOnlyHasMailNotScope() throws {
        let localOnlyNoMail = try localOnlyInput(services: [.vaultwarden])
        let bundle = try MailRecipe().generate(from: localOnlyNoMail)
        let script = try XCTUnwrap(artifact("setup-mail-server.sh", in: bundle)).contents
        XCTAssertFalse(script.contains("GRYONIXNEXUS_DNS_CHECK_FAILED"),
                       "no mail selected — the existing hasMail-gated DNS check must not appear, " +
                       "local-only or not")
    }

    func testFirewallIsNotYetRestrictedToTheLANForLocalOnly() throws {
        let bundle = try MailRecipe().generate(from: try localOnlyInput(services: [.vaultwarden]))
        let script = try XCTUnwrap(artifact("setup-mail-server.sh", in: bundle)).contents
        XCTAssertTrue(script.contains("accept comment \"mail + HTTP for ACME\""),
                      "the forwarded-ports rule still accepts unconditionally, not scoped to a LAN CIDR")
    }
}
