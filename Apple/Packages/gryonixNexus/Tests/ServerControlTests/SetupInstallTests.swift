import XCTest
@testable import ServerControl

final class SetupProgressParserTests: XCTestCase {
    func testStepMarkersDriveProgress() {
        var parser = SetupProgressParser()
        let events = parser.consume("echo start\nGRYONIXNEXUS_STEP 1/4\n==> Installing packages\n")
        XCTAssertEqual(events, [
            .line("echo start"),
            .step(index: 1, total: 4),
            .stage("Installing packages"),
            .line("==> Installing packages")
        ])
        XCTAssertEqual(parser.currentStep?.index, 1)
        XCTAssertEqual(parser.currentStep?.total, 4)
    }

    func testChunksMaySplitLinesAnywhere() {
        var parser = SetupProgressParser()
        var events = parser.consume("GRYONIXNEXUS_ST")
        XCTAssertEqual(events, [])
        events = parser.consume("EP 2/3\npartial")
        XCTAssertEqual(events, [.step(index: 2, total: 3)])
        events = parser.finish()
        XCTAssertEqual(events, [.line("partial")])
    }

    func testReportIsExtractedBetweenMarkers() {
        var parser = SetupProgressParser()
        let output = """
        GRYONIXNEXUS_REPORT_BEGIN
        ==> REPORT
        Domain: example.com
        GRYONIXNEXUS_REPORT_END
        GRYONIXNEXUS_DONE
        """
        let events = parser.consume(output + "\n")
        XCTAssertTrue(events.contains(.report("==> REPORT\nDomain: example.com")))
        XCTAssertTrue(events.contains(.done))
        XCTAssertTrue(parser.sawDone)
        // Report lines still show up in the plain log.
        XCTAssertTrue(events.contains(.line("Domain: example.com")))
    }

    func testANSIAndCarriageReturnNoiseIsStripped() {
        var parser = SetupProgressParser()
        let events = parser.consume("\u{1B}[32mdownloading 10%\rdownloading 100%\u{1B}[0m\n")
        XCTAssertEqual(events, [.line("downloading 100%")])
    }

    func testWithoutDoneMarkerSawDoneStaysFalse() {
        var parser = SetupProgressParser()
        _ = parser.consume("GRYONIXNEXUS_STEP 1/1\nsome output\n")
        XCTAssertFalse(parser.sawDone)
    }
}

final class SetupInstallerTests: XCTestCase {
    private let script = "#!/usr/bin/env bash\necho hi\n"

    private func stubHappyPath(_ fake: FakeSSHCommandRunner, runOutput: String) {
        fake.stub("cat > ")                     // upload on stdin
        fake.stub("setsid")                     // detached launch
        fake.stub("wc -l", stdout: runOutput)   // the follower
        fake.stub("rm -f")                      // wipe
    }

    private func collect(_ installer: SetupInstaller) async throws -> [SetupEvent] {
        var events: [SetupEvent] = []
        for try await event in installer.install(script: script, fileName: "setup-vps.sh") {
            events.append(event)
        }
        return events
    }

    private static let done = "GRYONIXNEXUS_DONE\nGRYONIXNEXUS_EXIT:0\n"

    func testUploadsLaunchesDetachedFollowsAndWipes() async throws {
        let fake = FakeSSHCommandRunner()
        stubHappyPath(fake, runOutput: "GRYONIXNEXUS_STEP 1/1\n==> Firewall\n" + Self.done)
        let installer = SetupInstaller(runner: fake, sleeper: FakeSleeper())

        let events = try await collect(installer)
        XCTAssertEqual(events.first, .step(index: 1, total: 1))
        XCTAssertTrue(events.contains(.stage("Firewall")))
        XCTAssertEqual(events.last, .done)

        let commands = fake.calls.map(\.command)
        XCTAssertTrue(commands[0].contains("umask 077"), "secrets-safe umask before writing")
        let launch = try XCTUnwrap(commands.first { $0.contains("setsid") })
        XCTAssertTrue(launch.contains("bash "))
        XCTAssertTrue(launch.contains("setup-vps.sh.log"))
        XCTAssertTrue(launch.hasSuffix("&"), "the launcher must return immediately")
        XCTAssertFalse(commands.contains { $0.hasPrefix("bash 'setup-vps.sh'") },
                       "the script must not run attached to the channel")
        XCTAssertTrue(commands.last!.contains("rm -f"))
        XCTAssertTrue(commands.last!.contains("setup-vps.sh.log"))
        XCTAssertEqual(fake.fed, [script], "the script travels on stdin, never in a command")
    }

    func testNonRootUserRunsThroughSudo() async throws {
        let fake = FakeSSHCommandRunner()
        stubHappyPath(fake, runOutput: Self.done)
        let installer = SetupInstaller(runner: fake, username: "admin", sleeper: FakeSleeper())
        _ = try await collect(installer)
        XCTAssertTrue(fake.calls.map(\.command).contains { $0.contains("sudo -n bash ") })
    }

    func testMissingDoneMarkerFailsEvenOnCleanExit() async throws {
        let fake = FakeSSHCommandRunner()
        stubHappyPath(fake, runOutput: "GRYONIXNEXUS_STEP 1/2\nsomething stopped\nGRYONIXNEXUS_EXIT:0\n")
        let installer = SetupInstaller(runner: fake, sleeper: FakeSleeper())
        do {
            _ = try await collect(installer)
            XCTFail("expected commandFailed")
        } catch let error as ServerControlError {
            guard case .commandFailed(_, _, let stderr) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertTrue(stderr.contains("something stopped"), "log tail attached for diagnosis")
        }
        XCTAssertTrue(fake.calls.last!.command.contains("rm -f"), "script wiped after failure too")
    }

    func testNonZeroExitSentinelIsReportedWithItsCode() async throws {
        let fake = FakeSSHCommandRunner()
        stubHappyPath(fake, runOutput: "GRYONIXNEXUS_STEP 1/3\nERROR: DNS check failed\nGRYONIXNEXUS_EXIT:1\n")
        let installer = SetupInstaller(runner: fake, sleeper: FakeSleeper())
        do {
            _ = try await collect(installer)
            XCTFail("expected commandFailed")
        } catch let error as ServerControlError {
            guard case .commandFailed(_, let code, let stderr) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertEqual(code, 1)
            XCTAssertTrue(stderr.contains("DNS check failed"))
        }
    }

    func testExitSentinelIsNotShownToTheUser() async throws {
        let fake = FakeSSHCommandRunner()
        stubHappyPath(fake, runOutput: "==> Firewall\n" + Self.done)
        let installer = SetupInstaller(runner: fake, sleeper: FakeSleeper())
        let events = try await collect(installer)
        XCTAssertFalse(events.contains { event in
            if case .line(let text) = event { return text.contains("GRYONIXNEXUS_EXIT") }
            return false
        })
    }

    // MARK: - Dropped connections

    func testDroppedConnectionReattachesAndResumesWithoutLosingLines() async throws {
        let fake = FakeSSHCommandRunner()
        fake.stub("cat > ")
        fake.stub("setsid")
        // First attach delivers two complete lines, then the session dies.
        fake.stub("wc -l", stdout: "GRYONIXNEXUS_STEP 1/2\n==> Firewall\n")
        fake.stubFailure("wc -l", error: ServerControlError.timeout(command: "follow"))
        // Second attach picks up the rest.
        fake.stub("wc -l", stdout: "GRYONIXNEXUS_STEP 2/2\n" + Self.done)
        fake.stub("rm -f")

        let installer = SetupInstaller(runner: fake, sleeper: FakeSleeper())
        let events = try await collect(installer)

        XCTAssertTrue(events.contains(.step(index: 1, total: 2)))
        XCTAssertTrue(events.contains(.reconnecting(attempt: 1)))
        XCTAssertTrue(events.contains(.step(index: 2, total: 2)))
        XCTAssertEqual(events.last, .done)

        let follows = fake.calls.map(\.command).filter { $0.contains("wc -l") }
        XCTAssertEqual(follows.count, 3)
        XCTAssertTrue(follows[0].contains("n=1"), "first attach starts at line 1")
        XCTAssertTrue(follows[1].contains("n=3"), "retry resumes after the 2 delivered lines")
        XCTAssertTrue(follows[2].contains("n=3"), "and again from the same point")
        XCTAssertEqual(fake.disconnects, 2, "the dead session is dropped before re-attaching")
    }

    func testReattachBudgetCountsConsecutiveDropsNotTotalOnes() async throws {
        let fake = FakeSSHCommandRunner()
        fake.stub("cat > ")
        fake.stub("setsid")
        for step in 1...8 {
            fake.stub("wc -l", stdout: "GRYONIXNEXUS_STEP \(step)/9\n")
            fake.stubFailure("wc -l", error: ServerControlError.timeout(command: "follow"))
        }
        fake.stub("wc -l", stdout: "GRYONIXNEXUS_STEP 9/9\n" + Self.done)
        fake.stub("rm -f")

        let installer = SetupInstaller(runner: fake, sleeper: FakeSleeper())
        let events = try await collect(installer)

        XCTAssertEqual(events.last, .done, "the run finished; only the app's view of it kept dropping")
        XCTAssertTrue(events.contains(.step(index: 9, total: 9)))
        XCTAssertEqual(events.filter { $0 == .reconnecting(attempt: 1) }.count, 8)
    }

    func testPartialLineAcrossADropIsNotDuplicated() async throws {
        let fake = FakeSSHCommandRunner()
        fake.stub("cat > ")
        fake.stub("setsid")
        // "==> Firew" arrives with no newline, then the connection dies.
        fake.stub("wc -l", stdout: "GRYONIXNEXUS_STEP 1/1\n==> Firew")
        fake.stubFailure("wc -l", error: ServerControlError.timeout(command: "follow"))
        fake.stub("wc -l", stdout: "==> Firewall\n" + Self.done)
        fake.stub("rm -f")

        let installer = SetupInstaller(runner: fake, sleeper: FakeSleeper())
        let events = try await collect(installer)

        XCTAssertTrue(events.contains(.stage("Firewall")))
        XCTAssertFalse(events.contains(.stage("Firew==> Firewall")), "buffered half must be dropped")
        XCTAssertFalse(events.contains { event in
            if case .line(let text) = event { return text.contains("Firew==>") }
            return false
        })
    }

    func testReattachingGivesUpAfterTheBoundAndLeavesTheRunningInstallsLog() async throws {
        let fake = FakeSSHCommandRunner()
        fake.stub("cat > ")
        fake.stub("setsid")
        for _ in 0...5 {
            fake.stubFailure("wc -l", error: ServerControlError.timeout(command: "follow"))
        }
        fake.stub("rm -f")

        let installer = SetupInstaller(runner: fake, sleeper: FakeSleeper())
        do {
            _ = try await collect(installer)
            XCTFail("expected failure after the reattach bound")
        } catch let error as ServerControlError {
            XCTAssertEqual(error, .installUnfollowable,
                           "the install is not what failed — the following of it is")
        }
        let follows = fake.calls.map(\.command).filter { $0.contains("wc -l") }
        XCTAssertEqual(follows.count, 6, "one initial attach plus five retries")
        XCTAssertFalse(fake.calls.contains { $0.command.contains(".b64") },
                       "the install is still running; its log is how the app finds it again")
    }

    func testTransportFailureDuringUploadWipesScript() async throws {
        let fake = FakeSSHCommandRunner()
        fake.stubFailure("cat > ", error: ServerControlError.timeout(command: "upload"))
        fake.stub("rm -f")
        let installer = SetupInstaller(runner: fake, sleeper: FakeSleeper())
        do {
            _ = try await collect(installer)
            XCTFail("expected timeout")
        } catch let error as ServerControlError {
            XCTAssertEqual(error, .timeout(command: "upload"))
        }
        XCTAssertTrue(fake.calls.last!.command.contains("rm -f"))
    }
}
