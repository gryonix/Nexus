import XCTest
import gryonixNexusCore
@testable import MailRecipe

private final class FixedKeyProvider: WireGuardKeyProvider, @unchecked Sendable {
    private var next = 0
    private let pairs = [
        WireGuardKeyPair(privateKey: "TEST-VPS-PRIVATE-KEY=", publicKey: "TEST-VPS-PUBLIC-KEY="),
        WireGuardKeyPair(privateKey: "TEST-HOME-PRIVATE-KEY=", publicKey: "TEST-HOME-PUBLIC-KEY=")
    ]

    func makeKeyPair(for slot: WireGuardKeySlot) throws -> WireGuardKeyPair {
        defer { next += 1 }
        return pairs[next % pairs.count]
    }
}

final class MailRecipeTests: XCTestCase {
    // MARK: - Helpers

    private func recipe() -> MailRecipe {
        MailRecipe(keyProvider: FixedKeyProvider())
    }

    private func inputA() throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [
                ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"), distribution: .debian)
            ]
        )
    }

    private func inputB() throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .vpsRelayWithHomeBackend,
            servers: [
                ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"), vpnAddress: .ipv4("10.8.0.1"), distribution: .debian),
                ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.8.0.2"), distribution: .debian)
            ]
        )
    }

    private func artifact(_ name: String, in bundle: GeneratedBundle) throws -> Artifact {
        try XCTUnwrap(bundle.artifacts.first { $0.fileName == name }, "missing artifact \(name)")
    }

    // MARK: - Strictly no more than two .sh scripts

    func testScenarioAProducesSingleScriptPlusDNS() throws {
        let bundle = try recipe().generate(from: inputA())
        XCTAssertEqual(
            Set(bundle.artifacts.map(\.fileName)),
            ["dns-records.txt", "example.com-dns-zone.txt", "example.com-dns-records.csv", "setup-mail-server.sh"],
            "scenario A: exactly one .sh plus DNS records (manual, zone file, CSV), no intermediate configs"
        )
        let scripts = bundle.artifacts.filter { $0.fileName.hasSuffix(".sh") }
        XCTAssertEqual(scripts.count, 1)
    }

    func testScenarioBProducesTwoScriptsPlusDNS() throws {
        let bundle = try recipe().generate(from: inputB())
        XCTAssertEqual(
            Set(bundle.artifacts.map(\.fileName)),
            ["dns-records.txt", "example.com-dns-zone.txt", "example.com-dns-records.csv", "setup-vps.sh", "setup-home-server.sh"],
            "scenario B: exactly two .sh (one per machine) plus DNS records (manual, zone file, CSV)"
        )
        XCTAssertEqual(bundle.artifacts.filter { $0.fileName.hasSuffix(".sh") }.count, 2)
    }

    /// Each service installs on its own, then one script finishes
    func testEveryServiceHasItsOwnScriptAndOneFinishes() throws {
        let bundle = try recipe().generate(from: inputB())
        let names = bundle.serviceScripts.map(\.fileName)
        XCTAssertEqual(names.last, "finish-setup.sh")
        XCTAssertEqual(Array(names.dropLast()), ["service-mailcow.sh"])
        XCTAssertTrue(bundle.serviceScripts.allSatisfy { $0.server == .homeBackend }, "services run at home")
        let mail = try XCTUnwrap(bundle.serviceScripts.first)
        XCTAssertTrue(mail.contents.contains("set -euo pipefail"))
        XCTAssertTrue(mail.contents.contains("mailcow-dockerized"), "the service itself")
        XCTAssertFalse(mail.contents.contains("nft -f"), "not the host setup again")
        XCTAssertTrue(mail.contents.hasSuffix("echo \"\(SetupMarkers.done)\""))
        let finish = try XCTUnwrap(bundle.serviceScripts.last)
        XCTAssertTrue(finish.contents.contains(SetupMarkers.reportBegin), "the report with the passwords")
        XCTAssertEqual(bundle.artifacts.filter { $0.fileName.hasSuffix(".sh") }.count, 2,
                       "the shared bundle still has one script per machine")
    }

    // MARK: - Importable DNS artifacts

    /// dns-records.txt must tell a non-expert exactly what to type
    func testDNSRecordsSpellOutEveryFieldAndTheCloudflareTraps() throws {
        let text = try artifact("dns-records.txt", in: try recipe().generate(from: inputA())).contents
        XCTAssertTrue(text.contains("Type: A") && text.contains("Type: MX"),
                      "each record names its type in plain words")
        XCTAssertTrue(text.contains("Name: mail"), "subdomains are given as the label the form wants")
        XCTAssertTrue(text.contains("Name: @"), "the domain itself is '@' in most panels")
        XCTAssertTrue(text.contains("Priority: 10"), "MX needs its priority spelled out")
        XCTAssertTrue(text.contains("DNS only"),
                      "the Cloudflare proxy switch has to be called out — orange cloud breaks mail")
        XCTAssertTrue(text.contains("example.com-dns-zone.txt") && text.contains("example.com-dns-records.csv"),
                      "the importable files are named so they can be found")
        XCTAssertTrue(text.contains("Import DNS records"),
                      "the exact Cloudflare menu path, not a vague 'import it somewhere'")
    }

    /// The zone file is machine input
    func testZoneFileIsPlainASCIIAndUploadable() throws {
        let base = try inputA()
        let input = MailRecipeInput(
            domain: base.domain, hostname: base.hostname, topology: base.topology,
            servers: base.servers, services: base.services, language: .ru)
        let bundle = try recipe().generate(from: input)
        let zone = try artifact("example.com-dns-zone.txt", in: bundle)
        XCTAssertTrue(zone.contents.allSatisfy(\.isASCII),
                      "a localised comment would put non-ASCII bytes into the importer's input")
        XCTAssertTrue(zone.contents.contains("$ORIGIN example.com."))
        XCTAssertFalse(zone.fileName.hasSuffix(".zone"),
                       "upload dialogs expect .txt; the extension is arbitrary to BIND itself")
    }

    /// The app finds the importable files by these exact names
    func testImportableArtifactsUseTheNamesTheAppLooksFor() throws {
        let bundle = try recipe().generate(from: inputA())
        let names = Set(bundle.artifacts.map(\.fileName))
        XCTAssertTrue(names.contains(DNSRecordGenerator.zoneFileName(domain: "example.com")))
        XCTAssertTrue(names.contains(DNSRecordGenerator.csvFileName(domain: "example.com")))
    }

    func testBINDZoneFileShape() throws {
        let bundle = try recipe().generate(from: inputA())
        let zone = try artifact("example.com-dns-zone.txt", in: bundle)
        XCTAssertEqual(zone.kind, .dnsRecord)
        XCTAssertNil(zone.server, "DNS artifacts aren't tied to a specific node")
        let contents = zone.contents
        XCTAssertTrue(contents.contains("$ORIGIN example.com."))
        XCTAssertTrue(contents.contains("$TTL 3600"))
        XCTAssertTrue(contents.contains("mail.example.com.    3600    IN A    203.0.113.10"))
        XCTAssertTrue(contents.contains("example.com.    3600    IN MX 10    mail.example.com."))
        XCTAssertTrue(contents.contains("example.com.    3600    IN TXT    \"v=spf1 mx -all\""))
        XCTAssertTrue(contents.contains("_dmarc.example.com.    3600    IN TXT"))
        XCTAssertFalse(contents.contains(" SOA "))
        XCTAssertFalse(contents.contains(" NS "))
    }

    func testDNSCSVShape() throws {
        let bundle = try recipe().generate(from: inputA())
        let csv = try artifact("example.com-dns-records.csv", in: bundle)
        XCTAssertEqual(csv.kind, .dnsRecord)
        XCTAssertNil(csv.server)
        XCTAssertTrue(csv.contents.hasSuffix("\n"), "the last row has no line terminator")
        let lines = csv.contents.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.first, "type,name,value,ttl,priority")
        XCTAssertTrue(lines.contains("A,mail.example.com,203.0.113.10,3600,"))
        XCTAssertTrue(lines.contains("MX,example.com,mail.example.com,3600,10"))
        XCTAssertTrue(lines.contains("TXT,example.com,v=spf1 mx -all,3600,"))
        // Every row (after the header) has exactly 5 CSV fields.
        for line in lines.dropFirst() {
            XCTAssertEqual(line.split(separator: ",", omittingEmptySubsequences: false).count, 5, line)
        }
    }

    func testDNSZoneAndCSVCarrySameRecordCountAsManualFile() throws {
        for input in [try inputA(), try inputB()] {
            let bundle = try recipe().generate(from: input)
            let recordCount = DNSRecordGenerator().records(in: MailContext(
                input: input, renderer: StringTemplateRenderer()
            )).count
            let csv = try artifact("example.com-dns-records.csv", in: bundle).contents
            let csvRows = csv.components(separatedBy: "\n").dropFirst().filter { !$0.isEmpty }
            XCTAssertEqual(csvRows.count, recordCount, "CSV must carry exactly the structured record set")
        }
    }

    // MARK: - Script requirements

    func testScriptsAreSelfContainedAndSafe() throws {
        for input in [try inputA(), try inputB()] {
            let bundle = try recipe().generate(from: input)
            for script in bundle.artifacts where script.kind == .shellScript {
                let text = script.contents
                XCTAssertTrue(text.hasPrefix("#!/usr/bin/env bash"), "\(script.fileName): shebang")
                XCTAssertTrue(text.contains("set -euo pipefail"), "\(script.fileName): strict mode")
                XCTAssertTrue(text.contains("\numask 022\n"), "\(script.fileName): umask is pinned, not inherited")
                XCTAssertTrue(text.contains(#"[ "$(id -u)" -eq 0 ]"#), "\(script.fileName): root check")
                XCTAssertTrue(text.contains(#"gd_os_release="${GRYONIXNEXUS_OS_RELEASE:-/etc/os-release}""#),
                              "\(script.fileName): distribution check")
                XCTAssertTrue(text.contains(#". "$gd_os_release""#),
                              "\(script.fileName): distribution check reads os-release")
                XCTAssertTrue(text.contains("DEBIAN_FRONTEND=noninteractive"), "\(script.fileName): non-interactive")
                XCTAssertTrue(text.contains("backup()"), "\(script.fileName): configs are backed up before overwrite")
                XCTAssertTrue(text.contains("log \"REPORT\""), "\(script.fileName): report at the end of the script")
            }
        }
    }

    func testScenarioAScriptCoversWholeMailStack() throws {
        let bundle = try recipe().generate(from: inputA())
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("cat > /etc/nftables.conf"), "firewall inside the script")
        XCTAssertTrue(script.contains("mailcow-dockerized"), "the mail stack is mailcow")
        XCTAssertTrue(script.contains("MAILCOW_HOSTNAME=mail.example.com"))
        XCTAssertTrue(script.contains("$MC_API/add/dkim"), "DKIM is provisioned over mailcow's API")
    }

    func testPTRDefaultsToRelaySubdomain() throws {
        let bundle = try recipe().generate(from: inputA())
        let dns = try artifact("dns-records.txt", in: bundle).contents
        XCTAssertTrue(dns.contains("relay.example.com."),
                      "the PTR note and its forward A record use relay.<domain> by default")
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("relay.example.com"),
                      "the report's PTR reminder uses the rDNS hostname")
    }

    func testCustomPTRHostnameIsUsedEverywhere() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            reverseDNSHostname: "out.example.com",
            topology: .singleHost,
            servers: [
                ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"), distribution: .debian)
            ]
        )
        let bundle = try recipe().generate(from: input)
        let dns = try artifact("dns-records.txt", in: bundle).contents
        XCTAssertTrue(dns.contains("out.example.com."))
        XCTAssertFalse(dns.contains("relay.example.com"))
        let script = try artifact("setup-mail-server.sh", in: bundle).contents
        XCTAssertTrue(script.contains("out.example.com"),
                      "the report's PTR reminder uses the custom rDNS hostname")
    }

    func testInvalidPTRHostnameIsRejected() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            reverseDNSHostname: "not a hostname",
            topology: .singleHost,
            servers: [
                ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"), distribution: .debian)
            ]
        )
        XCTAssertThrowsError(try recipe().generate(from: input))
    }

    func testScenarioADNSPointsToHost() throws {
        let bundle = try recipe().generate(from: inputA())
        let dns = try artifact("dns-records.txt", in: bundle)
        XCTAssertTrue(dns.contents.contains("203.0.113.10"))
        XCTAssertTrue(dns.contents.contains("IN MX 10    mail.example.com."))
        XCTAssertTrue(dns.contents.contains("v=spf1 mx -all"))
        XCTAssertTrue(dns.contents.contains("_dmarc.example.com."))
    }

    // MARK: - Scenario B

    func testScenarioBDNSPointsToVPS() throws {
        let bundle = try recipe().generate(from: inputB())
        let dns = try artifact("dns-records.txt", in: bundle)
        XCTAssertTrue(dns.contents.contains("203.0.113.10"), "the A record must point at the VPS")
    }

    func testVPSScriptForwardsMailIntoTunnel() throws {
        let bundle = try recipe().generate(from: inputB())
        let script = try artifact("setup-vps.sh", in: bundle)
        XCTAssertEqual(script.server, .vpsRelay)
        XCTAssertTrue(script.contents.contains("dnat to $home_ip"))
        XCTAssertTrue(script.contents.contains("define home_ip = 10.8.0.2"))
        XCTAssertTrue(script.contents.contains("ip saddr 10.8.0.0/24 masquerade"),
                      "MASQUERADE outward — outgoing mail uses the VPS IP")
        XCTAssertFalse(script.contents.contains("oifname \"wg0\" ip daddr $home_ip masquerade"),
                       "relayed public traffic must not collapse into a single tunnel source")
        XCTAssertTrue(script.contents.contains("iifname \"wg0\" oifname \"wg0\" ip daddr $home_ip snat to $hairpin_src"),
                      "hairpin SNAT for VPN-client traffic must still be present")
        XCTAssertTrue(script.contents.contains("net.ipv4.ip_forward = 1"), "forwarding is enabled by the script")
        // The public interface isn't guessed — it's determined at runtime.
        XCTAssertTrue(script.contents.contains("ip -4 route get 1.1.1.1"))
        XCTAssertTrue(script.contents.contains("sed -i \"s|@PUB_IF@|$PUB_IF|g\""))
        XCTAssertFalse(script.contents.contains("eth0"), "the interface is not hardcoded")
    }

    func testHomeScriptRunsMailBehindTheTunnel() throws {
        let bundle = try recipe().generate(from: inputB())
        let script = try artifact("setup-home-server.sh", in: bundle)
        XCTAssertEqual(script.server, .homeBackend)
        XCTAssertTrue(script.contents.contains("mailcow-dockerized"), "mail lives on the home node")
        XCTAssertTrue(script.contents.contains("AllowedIPs = 0.0.0.0/0"), "full tunnel")
        XCTAssertTrue(script.contents.contains("Endpoint = 203.0.113.10:51820"))
        XCTAssertTrue(script.contents.contains("PersistentKeepalive = 25"))
        XCTAssertTrue(script.contents.contains("latest-handshakes"), "the script waits for the VPS handshake")
    }

    // MARK: - WireGuard keys

    func testWireGuardPrivateKeysStayOnTheirMachines() throws {
        let bundle = try recipe().generate(from: inputB())
        let vps = try artifact("setup-vps.sh", in: bundle).contents
        let home = try artifact("setup-home-server.sh", in: bundle).contents

        XCTAssertTrue(vps.contains("PrivateKey = TEST-VPS-PRIVATE-KEY="))
        XCTAssertTrue(vps.contains("PublicKey = TEST-HOME-PUBLIC-KEY="))
        XCTAssertFalse(vps.contains("TEST-HOME-PRIVATE-KEY="), "the other machine's private key must not land in the script")

        XCTAssertTrue(home.contains("PrivateKey = TEST-HOME-PRIVATE-KEY="))
        XCTAssertTrue(home.contains("PublicKey = TEST-VPS-PUBLIC-KEY="))
        XCTAssertFalse(home.contains("TEST-VPS-PRIVATE-KEY="), "the other machine's private key must not land in the script")

        XCTAssertFalse(vps.contains("<VPS_PRIVATE_KEY>"), "there must be no placeholders")
        XCTAssertFalse(home.contains("<HOME_PRIVATE_KEY>"), "there must be no placeholders")
    }

    func testCryptoKitProviderProducesWireGuardFormatKeys() throws {
        let pair = CryptoKitWireGuardKeyProvider().makeKeyPair(for: .vps)
        for key in [pair.privateKey, pair.publicKey] {
            XCTAssertEqual(key.count, 44)
            XCTAssertTrue(key.hasSuffix("="))
            XCTAssertEqual(Data(base64Encoded: key)?.count, 32)
        }
        XCTAssertNotEqual(pair.privateKey, pair.publicKey)
    }

    func testDKIMKeyNeverGeneratedInApp() throws {
        for input in [try inputA(), try inputB()] {
            let bundle = try recipe().generate(from: input)
            XCTAssertFalse(bundle.artifacts.contains { $0.kind == .keyMaterial },
                           "DKIM keys are generated on the server, not in the app")
            for script in bundle.artifacts
            where script.kind == .shellScript && script.fileName != "setup-vps.sh" {
                XCTAssertTrue(script.contents.contains("$MC_API/add/dkim"),
                              "\(script.fileName): the DKIM key must be provisioned by the script on the server")
            }
        }
    }

    // MARK: - Validation

    func testValidationRejectsMissingPublicIP() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost)]
        )
        XCTAssertThrowsError(try recipe().validate(input)) { error in
            XCTAssertEqual(error as? ValidationError, .missingPublicIP(role: .singleHost))
        }
    }

    func testValidationRejectsMissingVPNAddress() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .vpsRelayWithHomeBackend,
            servers: [
                ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"), vpnAddress: .ipv4("10.8.0.1")),
                ServerNode(role: .homeBackend)
            ]
        )
        XCTAssertThrowsError(try recipe().validate(input)) { error in
            XCTAssertEqual(error as? ValidationError, .missingVPNAddress(role: .homeBackend))
        }
    }

    func testValidationRejectsDifferentSubnets() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .vpsRelayWithHomeBackend,
            servers: [
                ServerNode(role: .vpsRelay, publicAddress: .ipv4("203.0.113.10"), vpnAddress: .ipv4("10.8.0.1")),
                ServerNode(role: .homeBackend, vpnAddress: .ipv4("10.9.0.2"))
            ]
        )
        XCTAssertThrowsError(try recipe().validate(input)) { error in
            guard case .inconsistentTopology = error as? ValidationError else {
                return XCTFail("expected inconsistentTopology, got: \(error)")
            }
        }
    }

    func testValidationRejectsBadHostname() throws {
        let input = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "not a hostname",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"))]
        )
        XCTAssertThrowsError(try recipe().validate(input)) { error in
            XCTAssertEqual(error as? ValidationError, .invalidHostname("not a hostname"))
        }
    }

    // MARK: - Localization of generated content

    func testGeneratedContentFollowsInputLanguage() throws {
        // Default language is English.
        let english = try recipe().generate(from: inputA())
        let englishScript = try artifact("setup-mail-server.sh", in: english).contents
        XCTAssertTrue(englishScript.contains("log \"REPORT\""))

        let russianInput = MailRecipeInput(
            domain: try Domain("example.com"),
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [
                ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"), distribution: .debian)
            ],
            language: .ru
        )
        let russian = try recipe().generate(from: russianInput)
        let russianScript = try artifact("setup-mail-server.sh", in: russian).contents
        XCTAssertTrue(russianScript.contains("log \"ОТЧЁТ\""))
        let dns = try artifact("dns-records.txt", in: russian).contents
        XCTAssertTrue(dns.contains("DNS-записи для example.com"))
        XCTAssertFalse(russian.notes.isEmpty)
        XCTAssertTrue(russian.notes.allSatisfy { $0.range(of: "[а-яА-ЯёЁ]", options: .regularExpression) != nil },
                      "all notes must be localized")
    }
}
