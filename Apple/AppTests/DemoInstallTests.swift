import ServerControl
import XCTest

@testable import gryonixNexus

final class DemoInstallTests: XCTestCase {
    private let followCommand = "sh -c 'grep \(SetupProgressParser.exitMarker) setup.sh.log'"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(true, forKey: DemoServer.enabledKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "demoFleetInstalled")
        UserDefaults.standard.removeObject(forKey: DemoServer.enabledKey)
        super.tearDown()
    }

    func testTheEmulatedMachineAnswersTheConnectionCheck() async throws {
        let runner = DemoInstallRunner(deployment: DemoServer.deployment())

        let result = try await runner.run("echo GRYONIXNEXUS_PING; . /etc/os-release",
                                          on: .vps, timeout: .seconds(5))

        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.stdout.contains("GRYONIXNEXUS_PING"),
                      "the check never gets its answer: \(result.stdout)")
    }

    func testAnEmulatedInstallReplaysTheScriptItIsGiven() async throws {
        let runner = DemoInstallRunner(deployment: DemoServer.deployment())
        let script = """
        log "Installing packages"
        log "Firewall (nftables, default-deny)"
        log "Web server and certificates"
        """
        try await upload(script, to: runner)

        var parser = SetupProgressParser()
        var events: [SetupEvent] = []
        for try await chunk in runner.stream(followCommand, on: .vps, timeout: .seconds(60)) {
            if case .stdout(let text) = chunk { events += parser.consume(text) }
        }

        XCTAssertTrue(parser.sawDone, "the emulated install never finished")
        XCTAssertEqual(parser.exitCode, 0)
        XCTAssertTrue(stages(events).contains("Installing packages"),
                      "the replay ignored the script's own stages: \(stages(events))")
        XCTAssertTrue(events.contains { if case .report = $0 { return true } else { return false } },
                      "the install wrote no report")
    }

    func testTheStepsCountedMatchTheStagesTheScriptCarries() {
        let script = "log \"One\"\nlog \"Two\"\n"
        let lines = DemoInstallLog.lines(script: script, services: ["Mail"], domain: "x.com")
        let steps = lines.filter { $0.text.hasPrefix("GRYONIXNEXUS_STEP") }
        XCTAssertEqual(steps.count, 3, "two stages and the report make three steps")
        XCTAssertTrue(steps.allSatisfy { $0.text.hasSuffix("/3") }, "the total moves mid-run")
    }

    func testAScriptWithNoStagesStillDrawsAnInstall() {
        let lines = DemoInstallLog.lines(script: "", services: [], domain: "x.com")
        XCTAssertFalse(lines.filter { $0.text.hasPrefix("==> ") }.isEmpty,
                       "an unreadable script leaves the screen blank")
    }

    func testAServerInstalledOnTheEmulatedMachineIsDemoUntilARealOneArrives() {
        let installed = UUID()
        XCTAssertFalse(DemoServer.isDemo(installed))

        DemoServer.remember(installed: installed)

        XCTAssertTrue(DemoServer.isDemo(installed))
        XCTAssertFalse(DemoServer.isBuiltIn(installed), "it is not one of the four shipped")
        var demo = DemoServer.deployment()
        demo.name = "emulated"
        XCTAssertTrue(DemoServer.fleetIsDemoOnly([demo]))
        let real = Deployment(name: "real", topology: .singleHost, domain: "example.com",
                              entry: HostEndpoint(host: "203.0.113.10", user: "root"))
        XCTAssertFalse(DemoServer.fleetIsDemoOnly([demo, real]),
                       "a real server has to take the demo fleet away")

        DemoServer.forget(installed: installed)
        XCTAssertFalse(DemoServer.isDemo(installed))
    }

    func testARealAddressIsNeverEmulated() {
        let real = Deployment(name: "pi", topology: .singleHost, domain: "home.example",
                              entry: HostEndpoint(host: "192.168.178.100", user: "admin"))
        let sample = Deployment(name: "try", topology: .singleHost, domain: "example.com",
                                entry: HostEndpoint(host: "203.0.113.10", user: "root"))
        DemoServer.remember(installed: real.id)
        DemoServer.remember(installed: sample.id)

        XCTAssertFalse(DemoServer.isDemo(real), "a real machine must get a real install")
        XCTAssertTrue(DemoServer.isDemo(sample))
        DemoServer.releaseReal([real, sample])
        XCTAssertFalse(DemoServer.isInstalled(real.id))
        XCTAssertTrue(DemoServer.isInstalled(sample.id))

        DemoServer.forget(installed: sample.id)
    }

    // MARK: - Helpers

    private func upload(_ script: String, to runner: DemoInstallRunner) async throws {
        let encoded = Data(script.utf8).base64EncodedString()
        _ = try await runner.run("printf '%s' '\(encoded)' >> 'setup.sh.b64'",
                                 on: .vps, timeout: .seconds(5))
        _ = try await runner.run("umask 077 && base64 -d 'setup.sh.b64' > 'setup.sh'",
                                 on: .vps, timeout: .seconds(5))
    }

    private func stages(_ events: [SetupEvent]) -> [String] {
        events.compactMap { if case .stage(let text) = $0 { return text } else { return nil } }
    }
}
