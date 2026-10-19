import XCTest
import gryonixNexusCore
import ServiceCatalog
@testable import MailRecipe

/// docker-mailserver, pinned over the GENERATED artifact
final class DockerMailserverTests: XCTestCase {
    private func input(services: Set<ServiceID> = [.dockerMailserver],
                       aliases: [String] = []) throws -> MailRecipeInput {
        MailRecipeInput(
            domain: try Domain("example.com"),
            additionalDomains: try aliases.map { try Domain($0) },
            hostname: "mail.example.com",
            topology: .singleHost,
            servers: [ServerNode(role: .singleHost, publicAddress: .ipv4("203.0.113.10"),
                                 distribution: .ubuntu)],
            services: services
        )
    }

    private func script(_ input: MailRecipeInput) throws -> String {
        let bundle = try MailRecipe().generate(from: input)
        return try XCTUnwrap(bundle.artifacts.first { $0.fileName == "setup-mail-server.sh" },
                             "missing setup script").contents
    }

    private func dns(_ input: MailRecipeInput) throws -> String {
        let bundle = try MailRecipe().generate(from: input)
        return try XCTUnwrap(bundle.artifacts.first { $0.fileName == "dns-records.txt" },
                             "missing DNS artifact").contents
    }

    // MARK: - Starting at all

    func testPlaceholderCertificateIsWrittenBeforeTheContainerStarts() throws {
        let script = try script(try input())
        let placeholder = try XCTUnwrap(script.range(of: "openssl req -x509"),
                                        "no placeholder certificate is generated")
        let start = try XCTUnwrap(script.range(of: "docker compose -p dockermailserver up -d"),
                                  "the mail stack is never started")
        XCTAssertTrue(placeholder.lowerBound < start.lowerBound,
                      "the placeholder certificate must exist before the first start, "
                      + "or the container crash-loops until Caddy has the real one")
        XCTAssertTrue(script.contains("/opt/docker-mailserver/certs/cert.pem"),
                      "the placeholder must land where SSL_CERT_PATH points")
        XCTAssertTrue(script.contains("chmod 600 /opt/docker-mailserver/certs/key.pem"),
                      "the private key stays root-only")
    }

    func testPlaceholderIsSkippedWhenACertificateIsAlreadyThere() throws {
        let script = try script(try input())
        XCTAssertTrue(script.contains("if [ ! -s /opt/docker-mailserver/certs/cert.pem ]"),
                      "the placeholder must be conditional on there being no certificate yet")
    }

    // MARK: - The first mailbox and the DKIM keys

    func testReadinessIsNotProbedWithTheAccountListing() throws {
        let script = try script(try input())
        XCTAssertTrue(script.contains("if dms_exec setup help"),
                      "readiness must be probed with a command that works on an empty install")
        XCTAssertFalse(script.contains("if dms_exec setup email list"),
                       "`setup email list` fails until the first account exists — it cannot gate the step")
    }

    func testTheAccountListingCannotKillTheStep() throws {
        let script = try script(try input())
        XCTAssertTrue(script.contains("dms_exec setup email list || true"),
                      "the listing runs for information only and must tolerate failure")
    }

    func testDKIMSelectorMatchesTheOneTheDNSArtifactPublishes() throws {
        let input = try input()
        let script = try script(input)
        XCTAssertTrue(script.contains("setup config dkim keysize 2048 selector dkim domain example.com"),
                      "the selector must be stated, not left to the engine's default")
        XCTAssertTrue(try dns(input).contains("dkim._domainkey.example.com"),
                      "the DNS artifact names the selector the key is minted with")
    }

    func testEveryMailDomainGetsItsOwnDKIMKey() throws {
        let script = try script(try input(aliases: ["alias.example"]))
        XCTAssertTrue(script.contains("selector dkim domain example.com"))
        XCTAssertTrue(script.contains("selector dkim domain alias.example"))
    }

    func testDKIMDumpReadsTheFileSetupConfigDkimActuallyWrites() throws {
        let script = try script(try input())
        let globLine = script.split(separator: "\n").first { $0.contains("for F in") }
        XCTAssertEqual(globLine?.trimmingCharacters(in: .whitespaces),
                       "for F in /opt/docker-mailserver/config/opendkim/keys/*/dkim.txt; do",
                       "the dump must glob the file setup config dkim really writes, not rspamd's own tree" +
                       " (a mention of the old, wrong path in an explanatory comment nearby is fine)")
        XCTAssertTrue(script.contains("GRYONIXNEXUS_DKIM dkim._domainkey."),
                      "the record name carries the same selector the key was minted with")
    }

    func testDKIMDumpParsesTheBINDWrappedKeyRatherThanEmittingItRaw() throws {
        let script = try script(try input())
        XCTAssertTrue(script.contains(#"grep -o '"[^"]*"'"#),
                      "the quoted segments of the BIND record must be extracted, not the raw file")
        XCTAssertFalse(script.contains("tr -d '\\r\\n\\t'"),
                       "stripping whitespace from the whole file leaves the zone-file syntax in the value")
    }

    func testDKIMMarkerLineDoesNotQuoteTheValueUnlikeMailcowAndMailu() throws {
        let script = try script(try input())
        let markerLine = script.split(separator: "\n").first { $0.contains("echo \"GRYONIXNEXUS_DKIM") }
        XCTAssertEqual(markerLine?.trimmingCharacters(in: .whitespaces),
                       #"echo "GRYONIXNEXUS_DKIM dkim._domainkey.$D $V""#,
                       "the value must be bare, matching mailcow's and Mailu's own marker lines")
    }

    func testListingAnInstallWithNoMailboxesIsNotAnError() throws {
        let script = try script(try input())
        XCTAssertTrue(script.contains("if [ -s /opt/docker-mailserver/config/postfix-accounts.cf ]; then"),
                      "an install with no mailboxes must list as empty, not as a failure")
    }

    func testDeletingAMailboxWaitsOutTheEnginesOwnCreationRace() throws {
        let script = try script(try input())
        let arm = try XCTUnwrap(script.range(of: "\n  del)\n").map {
            String(script[$0.lowerBound...].prefix(1400))
        }, "the wrapper has no del arm any more")

        XCTAssertTrue(arm.contains("DEL_TRY"), "a failed delete is not retried at all")
        XCTAssertTrue(arm.contains("sleep 2"), "the retry does not wait for anything")
        XCTAssertTrue(arm.contains(#"[ "$DEL_TRY" -ge 5 ]"#),
                      "the retry loop is unbounded — a wrapper under sudo must always terminate")
        let deletes = arm.split(separator: "\n").filter {
            $0.contains(#"setup email del -y "$ADDRESS""#)
        }
        XCTAssertEqual(deletes.count, 2, "expected a quiet retry and one loud final attempt")
        XCTAssertEqual(deletes.filter { !$0.contains("2>&1") }.count, 1,
                       "the last attempt must not silence stderr: \(deletes)")
        XCTAssertFalse(arm.contains("rm -rf"), "the wrapper must not delete paths itself")
    }

    // MARK: - Webmail

    func testWebmailTalksToTheNameOnTheCertificate() throws {
        let script = try script(try input())
        XCTAssertTrue(script.contains("ROUNDCUBEMAIL_DEFAULT_HOST: ssl://mail.example.com"),
                      "IMAP must be addressed by the certificate's name")
        XCTAssertTrue(script.contains("ROUNDCUBEMAIL_SMTP_SERVER: tls://mail.example.com"),
                      "submission must be addressed by the certificate's name")
        XCTAssertFalse(script.contains("ssl://mailserver"),
                       "the service name is not on the certificate")
        XCTAssertTrue(script.contains("      - mail.example.com"),
                      "the mail container must answer to that name inside the compose network")
    }

    func testWebmailDatabaseIsMountedWhereTheImageKeepsIt() throws {
        let script = try script(try input())
        XCTAssertTrue(script.contains("/opt/docker-mailserver/webmail-db:/var/roundcube/db"),
                      "the sqlite database must survive a container recreate")
        XCTAssertFalse(script.contains("/var/www/html/db"),
                       "nothing writes there — the volume would be silently empty")
    }

    // MARK: - Secrets

    func testNoMailboxPasswordIsEverADockerExecArgument() throws {
        let script = try script(try input())
        let offenders = script.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                guard line.contains("setup email add") || line.contains("setup email update") else {
                    return false
                }
                return line.range(of: #"setup email (add|update) "[^"]*" ""#,
                                  options: .regularExpression) != nil
            }
        XCTAssertTrue(offenders.isEmpty,
                      "a mailbox password reached the argv of docker exec: \(offenders)")
        XCTAssertTrue(script.contains(#"| timeout 120 docker exec -i mailserver setup email "$1" "$2""#),
                      "the setup step feeds the password through stdin")
        XCTAssertTrue(script.contains(#"| docker exec -i mailserver setup email add "$ADDRESS""#),
                      "the wrapper feeds the password through stdin")
    }

    // MARK: - DNS

    func testMailHostResolvesOnEveryMirroredName() throws {
        let input = try input(aliases: ["alias.example"])
        let dns = try dns(input)
        let script = try script(input)
        XCTAssertTrue(script.contains("mail.example.com, mail.alias.example {"),
                      "Caddy serves the mail host on both names")
        XCTAssertTrue(dns.contains("mail.example.com."), "the primary mail host needs an A record")
        XCTAssertTrue(dns.contains("mail.alias.example."), "so does the mirrored one")
    }
}
