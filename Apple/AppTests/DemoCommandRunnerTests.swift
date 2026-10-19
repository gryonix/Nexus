import ServerControl
import XCTest

@testable import gryonixNexus

final class DemoCommandRunnerTests: XCTestCase {
    private var runner: DemoCommandRunner { DemoCommandRunner(deployment: DemoServer.deployment()) }

    override func setUp() async throws {
        await DemoFleetState.shared.forgetEverything()
    }

    func testComposePSOutputParsesAsRunningContainers() async throws {
        let result = try await runner.run("sudo docker compose -p vaultwarden ps",
                                          on: .vps, timeout: .seconds(5))
        let statuses = try DockerComposePSParser.parse(result.stdout)
        XCTAssertFalse(statuses.isEmpty, "the demo dashboard shows one row per container")
        XCTAssertTrue(statuses.allSatisfy { $0.status.hasPrefix("Up ") },
                      "an untouched demo machine starts with everything running — a card of stopped services reads as a broken server")
        XCTAssertTrue(statuses.allSatisfy { $0.name.hasPrefix("vaultwarden-") },
                      "the containers must belong to the project that was asked about")
    }

    func testDockerPSOutputParsesAndNamesEveryServiceOfEveryDemoServer() async throws {
        for deployment in DemoServer.deployments() {
            let runner = DemoCommandRunner(deployment: deployment)
            let result = try await runner.run("sudo docker ps -a", on: .vps, timeout: .seconds(5))
            let all = try DockerPSParser.parse(result.stdout)
            for service in deployment.installedServices {
                XCTAssertNotNil(DockerPSParser.find(container: service.id.rawValue, in: all),
                                "\(service.id.rawValue) is installed on \(deployment.name), so its container has to be in the listing")
            }
        }
    }

    func testStoppingAServiceIsReflectedByTheNextStatusRead() async throws {
        _ = try await runner.run("sudo docker compose -p vaultwarden stop vaultwarden",
                                 on: .vps, timeout: .seconds(5))
        let stopped = try DockerPSParser.parse(
            try await runner.run("sudo docker ps -a", on: .vps, timeout: .seconds(5)).stdout)
        let row = try XCTUnwrap(DockerPSParser.find(container: "vaultwarden", in: stopped))
        XCTAssertTrue(row.status.hasPrefix("Exited"),
                      "the container the demo was just told to stop has to read as stopped, got: \(row.status)")

        _ = try await runner.run("sudo docker compose -p vaultwarden start vaultwarden",
                                 on: .vps, timeout: .seconds(5))
        let restarted = try DockerPSParser.parse(
            try await runner.run("sudo docker ps -a", on: .vps, timeout: .seconds(5)).stdout)
        let back = try XCTUnwrap(DockerPSParser.find(container: "vaultwarden", in: restarted))
        XCTAssertTrue(back.status.hasPrefix("Up "), "got: \(back.status)")
    }

    func testRemovingAServiceTakesItOutOfTheListing() async throws {
        let output = try await runner.run(
            "sudo /opt/gryonixnexus-uninstall.sh adguard-home", on: .vps, timeout: .seconds(5)).stdout
        XCTAssertTrue(output.contains(CommandCatalog.Uninstall.doneMarker),
                      "no marker means the app treats a clean run as a failure")
        let after = try DockerPSParser.parse(
            try await runner.run("sudo docker ps -a", on: .vps, timeout: .seconds(5)).stdout)
        XCTAssertNil(DockerPSParser.find(container: "adguard-home", in: after),
                     "a removed service that is still listed is a demo contradicting itself")
    }

    func testTheLockdownSwitchRemembersWhereItWasPut() async throws {
        func read() async throws -> String {
            try await runner.run(CommandCatalog.AdminLockdown.status,
                                 on: .vps, timeout: .seconds(5)).stdout
        }
        var state = try await read()
        XCTAssertEqual(state, "off")
        _ = try await runner.run(CommandCatalog.AdminLockdown.on, on: .vps, timeout: .seconds(5))
        state = try await read()
        XCTAssertEqual(state, "on")
        _ = try await runner.run(CommandCatalog.AdminLockdown.off, on: .vps, timeout: .seconds(5))
        state = try await read()
        XCTAssertEqual(state, "off")
    }

    func testARunBackupAppearsInTheListing() async throws {
        let before = BackupListParser.parse(
            try await runner.run("ls -lht '/opt/backups/vaultwarden'",
                                 on: .vps, timeout: .seconds(5)).stdout)
        let output = try await runner.run(
            "sudo /opt/gryonixnexus-backup-ctl.sh backup 'vaultwarden' --encrypt",
            on: .vps, timeout: .seconds(5)).stdout
        XCTAssertTrue(output.contains(CommandCatalog.Backups.controlDoneMarker), "got: \(output)")
        let after = BackupListParser.parse(
            try await runner.run("ls -lht '/opt/backups/vaultwarden'",
                                 on: .vps, timeout: .seconds(5)).stdout)
        XCTAssertEqual(after.count, before.count + 1,
                       "the backup the demo just took has to be in the list it takes them into")
    }

    func testReadingLogsIsImitated() async throws {
        let result = try await runner.run("sudo docker logs --tail 500 --timestamps vaultwarden",
                                          on: .vps, timeout: .seconds(5))
        XCTAssertTrue(result.stdout.contains("Listening on"), "an empty log reads as a failed connection")
    }
}

// MARK: - The host's own probes

final class DemoHostProbeTests: XCTestCase {
    override func setUp() async throws {
        await DemoFleetState.shared.forgetEverything()
    }

    private var relayPair: Deployment {
        DemoServer.deployments().first { $0.hasHomeHost }!
    }

    func testTheGeneralProbeAnswersAllThreeSectionsForEveryDemoServer() async throws {
        for deployment in DemoServer.deployments() {
            let runner = DemoCommandRunner(deployment: deployment)
            let config = deployment.dashboardConfig
            let status = try await StatusOperations(runner: runner, config: config)
                .generalVPSStatus()
            XCTAssertTrue(status.forwarding, "\(deployment.name): a demo machine forwards")
            XCTAssertTrue(status.selfPing.isAlive, "\(deployment.name): it answers its own ping")
            XCTAssertTrue(status.tunnelPing.isAlive, "\(deployment.name): the tunnel answers")
        }
    }

    func testForwardingIsReadableOnTheHomeMachine() async throws {
        let deployment = relayPair
        let ops = StatusOperations(runner: DemoCommandRunner(deployment: deployment),
                                   config: deployment.dashboardConfig)
        let forwarding = try await ops.ipForwarding(on: .home)
        XCTAssertTrue(forwarding)
    }

    func testDiskAndMemoryComeFromTheMachinesOwnProfile() async throws {
        let deployment = relayPair
        let ops = StatusOperations(runner: DemoCommandRunner(deployment: deployment),
                                   config: deployment.dashboardConfig)
        let profile = DemoServer.profile(deploymentID: deployment.id, host: .home)!

        let mounts = try await ops.disk(on: .home)
        let root = try XCTUnwrap(mounts.first { $0.target == "/" })
        XCTAssertEqual(root.sizeBytes, profile.diskTotalBytes)
        XCTAssertEqual(root.usedPercent, Int((profile.diskUsedFraction * 100).rounded()))

        let memory = try await ops.memory(on: .home)
        XCTAssertEqual(memory.memTotalBytes, profile.memTotalBytes)
        XCTAssertGreaterThan(memory.memUsedBytes, 0)
        XCTAssertLessThan(memory.memUsedBytes, memory.memTotalBytes)
    }

    func testEachEndOfTheTunnelReportsTheOtherAsItsPeer() async throws {
        let deployment = relayPair
        let ops = StatusOperations(runner: DemoCommandRunner(deployment: deployment),
                                   config: deployment.dashboardConfig)
        let relay = try await ops.wgStatus(on: .vps)
        let home = try await ops.wgStatus(on: .home)
        XCTAssertEqual(relay.interface.name, "wg0")
        let relayPeer = try XCTUnwrap(relay.peers.first)
        let homePeer = try XCTUnwrap(home.peers.first)
        XCTAssertNotEqual(relayPeer.endpoint, homePeer.endpoint,
                          "each end has to point at the other one, not at itself")
        XCTAssertNotEqual(relayPeer.allowedIPs, homePeer.allowedIPs)
    }

    func testTheCombinedMetricsProbeIsNotAnsweredWithADiskListing() async throws {
        let deployment = relayPair
        let result = try await DemoCommandRunner(deployment: deployment)
            .run(CommandCatalog.hostMetrics, on: .vps, timeout: .seconds(5))
        XCTAssertFalse(result.stdout.contains("1B-blocks"),
                       "the metrics probe must not be answered with df output")
        XCTAssertTrue(DemoHostMetrics.covers(deployment),
                      "which is only safe because the readings come from the profile instead")
    }
}
