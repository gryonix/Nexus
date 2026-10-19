import XCTest
import ServiceCatalog
@testable import ServerControl

final class MailboxOperationsTests: XCTestCase {
    private func deployment(topology: Topology = .vpsRelayWithHomeBackend,
                            services: Set<ServiceID> = [.dockerMailserver]) -> Deployment {
        Deployment(
            name: "Test",
            topology: topology,
            domain: "example.com",
            entry: HostEndpoint(host: "203.0.113.4", user: "admin"),
            homeWGAddress: topology == .vpsRelayWithHomeBackend ? "10.8.0.2" : nil,
            services: services
        )
    }

    private func ops(_ runner: FakeSSHCommandRunner,
                     deployment: Deployment? = nil) -> MailboxOperations {
        MailboxOperations(runner: runner, deployment: deployment ?? self.deployment())
    }

    private static let listing = """
    * postmaster@example.com ( 0 / ~ ) [0%]
    * anna+news@example.com ( 12M / ~ ) [1%]
    """

    // MARK: - Listing

    func testListUsesTheWrapperLiteralOnTheServicesHost() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("gryonixnexus-dms-mailbox.sh list", stdout: Self.listing)

        let mailboxes = try await ops(runner).list()

        XCTAssertEqual(mailboxes.map(\.address),
                       ["postmaster@example.com", "anna+news@example.com"])
        XCTAssertEqual(runner.calls, [.init(kind: .run,
                                            command: "sudo /opt/gryonixnexus-dms-mailbox.sh list",
                                            host: .home)])
    }

    func testListRunsOnTheSingleHostInScenarioA() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mailbox.sh list", stdout: Self.listing)

        _ = try await ops(runner, deployment: deployment(topology: .singleHost)).list()

        XCTAssertEqual(runner.calls.first?.host, .vps)
    }

    func testListSurfacesAStaleWhitelistAsSudoPasswordRequired() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mailbox.sh list", exitCode: 1,
                    stderr: "sudo: a password is required")

        do {
            _ = try await ops(runner).list()
            XCTFail("expected the stale-sudoers failure")
        } catch ServerControlError.sudoPasswordRequired {
            // expected
        }
    }

    func testEveryActionRefusesAServerWithoutTheEngine() async throws {
        let runner = FakeSSHCommandRunner()
        let other = deployment(services: [.mailcow])

        do {
            _ = try await ops(runner, deployment: other).list()
            XCTFail("expected a refusal")
        } catch ServerControlError.notConfigured {
            XCTAssertTrue(runner.calls.isEmpty, "nothing may reach a server without the engine")
        }
    }

    // MARK: - Adding

    func testAddSendsThePasswordOnStdinAndNeverInArgv() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mailbox.sh add", stdout: "GRYONIXNEXUS_MAILBOX_DONE add anna@example.com\n")

        try await ops(runner).add(address: "anna@example.com", password: "s3cr#t pass")

        let command = try XCTUnwrap(runner.calls.first?.command)
        XCTAssertEqual(command, "sudo /opt/gryonixnexus-dms-mailbox.sh add 'anna@example.com'")
        XCTAssertEqual(runner.fed, ["s3cr#t pass"])
    }

    func testAddQuotesAnAddressWithAPlusTag() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mailbox.sh add",
                    stdout: "GRYONIXNEXUS_MAILBOX_DONE add anna+news@example.com\n")

        try await ops(runner).add(address: "anna+news@example.com", password: "pw")

        XCTAssertTrue(try XCTUnwrap(runner.calls.first?.command)
            .hasSuffix("sudo /opt/gryonixnexus-dms-mailbox.sh add 'anna+news@example.com'"))
    }

    func testAddRefusesAnAddressTheWrapperWouldReject() async throws {
        let runner = FakeSSHCommandRunner()
        for address in ["-flag@example.com", "аня@example.com", "a@b@example.com",
                        "@example.com", "anna@", "anna example@example.com",
                        "anna;rm -rf@example.com", "annaexample.com"] {
            do {
                try await ops(runner).add(address: address, password: "pw")
                XCTFail("expected \(address) to be refused")
            } catch ServerControlError.notConfigured {
                // expected
            }
        }
        XCTAssertTrue(runner.calls.isEmpty, "a rejected address must not reach the server")
    }

    func testAddRefusesAnEmptyPassword() async throws {
        let runner = FakeSSHCommandRunner()

        do {
            try await ops(runner).add(address: "anna@example.com", password: "")
            XCTFail("expected a refusal")
        } catch ServerControlError.notConfigured {
            XCTAssertTrue(runner.calls.isEmpty)
        }
    }

    func testAFailedAddNeverEchoesTheCommandOrThePassword() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mailbox.sh add", exitCode: 2,
                    stderr: "setup: unexpected argument 's3cret'")

        do {
            try await ops(runner).add(address: "anna@example.com", password: "s3cret")
            XCTFail("expected the failure")
        } catch ServerControlError.commandFailed(let command, _, let stderr) {
            XCTAssertEqual(command, "add mailbox")
            XCTAssertFalse(stderr.contains("s3cret"))
            XCTAssertTrue(stderr.contains("***"))
        }
    }

    func testAMissingMarkerIsAFailureEvenOnExitZero() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mailbox.sh add", stdout: "")

        do {
            try await ops(runner).add(address: "anna@example.com", password: "pw")
            XCTFail("expected the failure")
        } catch ServerControlError.commandFailed(let command, _, _) {
            XCTAssertEqual(command, "add mailbox")
        }
    }

    // MARK: - Deleting / repassword

    func testDeleteUsesTheWrapperAndCarriesNoStdin() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mailbox.sh del", stdout: "GRYONIXNEXUS_MAILBOX_DONE del anna@example.com\n")

        try await ops(runner).delete(address: "anna@example.com")

        XCTAssertEqual(runner.calls.first?.command,
                       "sudo /opt/gryonixnexus-dms-mailbox.sh del 'anna@example.com'")
    }

    func testSetPasswordUsesThePasswordArmOnStdin() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mailbox.sh password",
                    stdout: "GRYONIXNEXUS_MAILBOX_DONE password anna@example.com\n")

        try await ops(runner).setPassword(address: "anna@example.com", password: "n3w")

        XCTAssertEqual(runner.calls.first?.command,
                       "sudo /opt/gryonixnexus-dms-mailbox.sh password 'anna@example.com'")
        XCTAssertEqual(runner.fed, ["n3w"])
    }

    func testAPasswordWithAQuoteTravelsUnchanged() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mailbox.sh password",
                    stdout: "GRYONIXNEXUS_MAILBOX_DONE password anna@example.com\n")

        try await ops(runner).setPassword(address: "anna@example.com", password: "it's ok")

        XCTAssertEqual(runner.fed, ["it's ok"])
        XCTAssertFalse(runner.calls.contains { $0.command.contains("it's") })
    }

    func testTheEnginesColouredFailureReachesTheUserAsPlainText() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mailbox.sh del", exitCode: 1, stderr:
            "2026-08-06 07:43:36+00:00 \u{1B}[1;31mERROR\u{1B}[0m delmailuser: "
            + "'anna@example.com' does not exist\n"
            + "2026-08-06 07:43:36+00:00 \u{1B}[1;31mERROR\u{1B}[0m delmailuser: Aborting\n")

        do {
            try await ops(runner).delete(address: "anna@example.com")
            XCTFail("expected the failure")
        } catch ServerControlError.commandFailed(_, _, let stderr) {
            XCTAssertFalse(stderr.contains("\u{1B}"), "ANSI escapes reached the user: \(stderr)")
            XCTAssertTrue(stderr.contains("does not exist"))
            // Trailing newlines are a blank line in an alert.
            XCTAssertFalse(stderr.hasSuffix("\n"))
        }
    }

    func testAFailedListingIsReportedWithoutANSI() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("mailbox.sh list", exitCode: 1,
                    stderr: "\u{1B}[31mError response from daemon\u{1B}[0m: container is not running\n")

        do {
            _ = try await ops(runner).list()
            XCTFail("expected the failure")
        } catch ServerControlError.commandFailed(_, _, let stderr) {
            XCTAssertEqual(stderr, "Error response from daemon: container is not running")
        }
    }

    // MARK: - Cross-module literals

    func testWrapperPathAndMarkerMatchTheGeneratedScript() throws {
        XCTAssertEqual(CommandCatalog.DockerMailserver.mailboxScriptPath,
                       DockerMailserverService.mailboxScriptPath)
        let context = deployment().serviceContext
        let script = DockerMailserverService().setupSteps(context).joined(separator: "\n")
        XCTAssertTrue(script.contains(CommandCatalog.DockerMailserver.mailboxScriptPath))
        XCTAssertTrue(script.contains(CommandCatalog.DockerMailserver.mailboxDoneMarker))
        for arm in ["list)", "add)", "del)", "password)"] {
            XCTAssertTrue(script.contains(arm), "the wrapper has no \(arm) arm any more")
        }
    }
}

final class MailboxListParserTests: XCTestCase {
    func testParsesQuotaRows() {
        let mailboxes = MailboxListParser.parse("""
        * postmaster@example.com ( 0 / ~ ) [0%]
        * anna+news@example.com ( 12M / 1G ) [1%]
        """)

        XCTAssertEqual(mailboxes.map(\.address),
                       ["postmaster@example.com", "anna+news@example.com"])
        XCTAssertEqual(mailboxes.first?.detail, "( 0 / ~ ) [0%]")
        XCTAssertEqual(mailboxes.last?.localPart, "anna+news")
        XCTAssertEqual(mailboxes.last?.domain, "example.com")
    }

    func testEmptyOutputIsAnEmptyList() {
        XCTAssertTrue(MailboxListParser.parse("").isEmpty)
        XCTAssertTrue(MailboxListParser.parse("\n\n  \n").isEmpty)
    }

    func testHeadersAndProseAreNotMailboxes() {
        let mailboxes = MailboxListParser.parse("""
        Accounts:
        WARN  no accounts exist yet
        Error: mailbox anna@example.com not found
        * anna@example.com ( 0 / ~ ) [0%]
        """)

        XCTAssertEqual(mailboxes.map(\.address), ["anna@example.com"])
    }

    func testBareAddressLinesAreAccepted() {
        // Not every version prints the quota columns.
        let mailboxes = MailboxListParser.parse("anna@example.com\nbob@example.com\n")

        XCTAssertEqual(mailboxes.map(\.address), ["anna@example.com", "bob@example.com"])
        XCTAssertNil(mailboxes.first?.detail)
    }

    func testANSIColoursAreStripped() {
        let mailboxes = MailboxListParser.parse("* \u{1B}[32manna@example.com\u{1B}[0m ( 0 / ~ )")

        XCTAssertEqual(mailboxes.map(\.address), ["anna@example.com"])
    }

    func testRepeatedAddressesAppearOnce() {
        let mailboxes = MailboxListParser.parse("""
        * anna@example.com ( 0 / ~ )
        * anna@example.com ( 0 / ~ )
        """)

        XCTAssertEqual(mailboxes.count, 1)
    }

    func testAUnicodeLocalPartIsListedButNotManageable() {
        let mailboxes = MailboxListParser.parse("* аня@example.com ( 0 / ~ ) [0%]")

        XCTAssertEqual(mailboxes.map(\.address), ["аня@example.com"])
        XCTAssertEqual(mailboxes.first?.isManageable, false)
        XCTAssertEqual(Mailbox(address: "anna+news@example.com").isManageable, true)
    }

    func testTheShapesOneLiveListingReallyPrints() {
        let mailboxes = MailboxListParser.parse("""
        * admin@example.com ( 6.0K / ~ ) [0%]

        * test=outside@example.com (  /  ) [%]

        * smoke.fresh@example.com ( 0 / ~ ) [0%]

        """)

        XCTAssertEqual(mailboxes.map(\.address),
                       ["admin@example.com", "test=outside@example.com", "smoke.fresh@example.com"])
        XCTAssertEqual(mailboxes[1].detail, "(  /  ) [%]")
        XCTAssertEqual(mailboxes[1].isManageable, false, "'=' is outside what the wrapper accepts")
        XCTAssertEqual(mailboxes[0].isManageable, true)
    }

    func testEngineDiagnosticsThatWrapAnAddressAreNotMailboxes() {
        let mailboxes = MailboxListParser.parse("""
        doveadm(test=outside@example.com): Error: User doesn't exist
        listmailuser: could not read anna@example.com, skipping
        <anna@example.com>: relay failed
        * anna@example.com ( 0 / ~ ) [0%]
        """)

        XCTAssertEqual(mailboxes.map(\.address), ["anna@example.com"])
    }
}
