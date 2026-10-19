import ServiceCatalog
import XCTest
@testable import ServerControl

final class HostWideOperationsTests: XCTestCase {
    // MARK: - Fixtures

    private func singleWorker() -> Deployment {
        Deployment(name: "A", topology: .singleHost, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                   services: [.vaultwarden])
    }

    private func twoWorkers() throws -> (Deployment, DeploymentNode) {
        var deployment = Deployment(name: "B", topology: .vpsRelayWithHomeBackend,
                                    domain: "example.com",
                                    entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                                    homeWGAddress: "10.8.0.2",
                                    services: [.vaultwarden, .nextcloud])
        let entry = try XCTUnwrap(deployment.nodes.first { $0.legacySlot == .vps })
        let third = DeploymentNode(id: UUID(),
                                   endpoint: HostEndpoint(host: "10.8.0.3", user: "root"),
                                   capabilities: [.worker], routedThrough: entry.id)
        try deployment.addNode(third)
        return (deployment, third)
    }

    private func hostsAsked(_ runner: FakeSSHCommandRunner) -> [SSHHostID] {
        runner.calls.map(\.host)
    }

    // MARK: - Which machines answer at all

    func testWorkerHostsIsEveryMachineThatRunsServices() throws {
        XCTAssertEqual(singleWorker().workerHosts, [.vps])

        let (deployment, third) = try twoWorkers()
        XCTAssertEqual(deployment.workerHosts, [.home, .node(third.id)])
        XCTAssertFalse(deployment.workerHosts.contains(.vps),
                       "the relay runs nothing, so no host-wide question may be put to it")
    }

    // MARK: - The update check

    func testTheCheckAsksOneMachineWhenThereIsOnlyOne() async throws {
        let runner = FakeSSHCommandRunner()
        let deployment = singleWorker()
        runner.stub("update", stdout: "\(CommandCatalog.Updates.currentMarker) vaultwarden\n")

        let reports = try await ServiceUpdateOperations(runner: runner, deployment: deployment).check()

        XCTAssertEqual(hostsAsked(runner), [deployment.servicesHost])
        XCTAssertEqual(reports.map(\.service), [.vaultwarden])
    }

    func testTheCheckMergesEveryWorkersAnswer() async throws {
        let runner = FakeSSHCommandRunner()
        let (deployment, third) = try twoWorkers()
        runner.stub("update", stdout: "\(CommandCatalog.Updates.currentMarker) vaultwarden\n")
        runner.stub("update", stdout: "\(CommandCatalog.Updates.availableMarker) nextcloud nextcloud:30\n")

        let reports = try await ServiceUpdateOperations(runner: runner, deployment: deployment).check()

        XCTAssertEqual(hostsAsked(runner), [.home, .node(third.id)])
        XCTAssertEqual(Set(reports.map(\.service)), [.vaultwarden, .nextcloud])
        let nextcloud = try XCTUnwrap(reports.first { $0.service == .nextcloud })
        XCTAssertEqual(nextcloud.status, .available(images: ["nextcloud:30"]))
    }

    // MARK: - The last run

    func testTheLastRunIsTheMostRecentAcrossMachines() async throws {
        let runner = FakeSSHCommandRunner()
        let (deployment, _) = try twoWorkers()
        let newer = "2026-08-25T10:00:00Z"
        let older = "2026-08-20T10:00:00Z"
        runner.stub("update", stdout: "last-run \(newer)\n\(CommandCatalog.Updates.updatedMarker) vaultwarden\n")
        runner.stub("update", stdout: "last-run \(older)\n\(CommandCatalog.Updates.failedMarker) nextcloud boom\n")

        let log = try await ServiceUpdateOperations(runner: runner, deployment: deployment).loadStatus()

        XCTAssertEqual(log.lastRun, ISO8601DateFormatter().date(from: newer))
        XCTAssertEqual(log.records.count, 2, "a machine's records were dropped")
    }

    // MARK: - Schedules

    func testAScheduleOnAnyWorkerReadsAsOn() {
        let off = AutoUpdateSettings(schedule: .off, services: [])
        let on = AutoUpdateSettings(schedule: .days(count: 7, hour: 3, minute: 0), services: ["nextcloud"])
        let merged = ServiceUpdateOperations.merged([off, on])

        XCTAssertEqual(merged.schedule, .days(count: 7, hour: 3, minute: 0))
        XCTAssertEqual(merged.services, ["nextcloud"])
        XCTAssertEqual(ServiceUpdateOperations.merged([off, off]).schedule, .off)
    }

    func testTheBackupScheduleKeepsTheLargestRetention() {
        let modest = AutoBackupSettings(schedule: .days(count: 1, hour: 4, minute: 30), retention: 3, services: ["vaultwarden"])
        let generous = AutoBackupSettings(schedule: .off, retention: 30, services: ["nextcloud"])
        let merged = AutoBackupOperations.merged([modest, generous])

        XCTAssertEqual(merged.schedule, .days(count: 1, hour: 4, minute: 30))
        XCTAssertEqual(merged.retention, 30)
        XCTAssertEqual(merged.services, ["vaultwarden", "nextcloud"])
    }

    /// Saving arms the timer on EVERY worker
    func testSavingTheUpdateScheduleArmsEveryWorker() async throws {
        let runner = FakeSSHCommandRunner()
        let (deployment, third) = try twoWorkers()
        runner.stub("update", stdout: CommandCatalog.Updates.doneMarker)
        runner.stub("update", stdout: CommandCatalog.Updates.doneMarker)

        try await ServiceUpdateOperations(runner: runner, deployment: deployment)
            .save(AutoUpdateSettings(schedule: .days(count: 7, hour: 3, minute: 0), services: ["vaultwarden"]))

        XCTAssertEqual(hostsAsked(runner), [.home, .node(third.id)])
    }

    func testSavingTheBackupScheduleArmsEveryWorker() async throws {
        let runner = FakeSSHCommandRunner()
        let (deployment, third) = try twoWorkers()
        runner.stub("backup", stdout: CommandCatalog.Backups.controlDoneMarker)
        runner.stub("backup", stdout: CommandCatalog.Backups.controlDoneMarker)

        try await AutoBackupOperations(runner: runner, deployment: deployment)
            .save(AutoBackupSettings(schedule: .days(count: 1, hour: 4, minute: 30), retention: 7, services: ["vaultwarden"]))

        XCTAssertEqual(hostsAsked(runner), [.home, .node(third.id)])
    }

    func testAWrapperWithoutDestinationVerbsSaysWhatToDo() async throws {
        let runner = FakeSSHCommandRunner()
        let deployment = singleWorker()
        runner.stub("backup", stdout: "",
                    exitCode: 2, stderr: "unsupported action: set-destination\n")

        do {
            try await AutoBackupOperations(runner: runner, deployment: deployment)
                .saveDestination(BackupDestinationSettings(kind: .ssh, host: "backup.example",
                                                           user: "root", path: "/backups"),
                                 secret: nil)
            XCTFail("an older wrapper reported success")
        } catch {
            let message = (error as? ServerControlError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(message.contains("Repair server"), message)
            XCTAssertFalse(message.contains("unsupported action"), message)
        }
    }

    func testTestingADestinationOnAnOlderWrapperSaysWhatToDo() async throws {
        let runner = FakeSSHCommandRunner()
        let deployment = singleWorker()
        runner.stub("backup", stdout: "",
                    exitCode: 2, stderr: "unsupported action: test-destination\n")

        let result = try await AutoBackupOperations(runner: runner, deployment: deployment)
            .testDestination()
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.detail.contains("Repair server"), result.detail)
    }

    func testARefusingWorkerFailsTheWholeSave() async throws {
        let runner = FakeSSHCommandRunner()
        let (deployment, _) = try twoWorkers()
        runner.stub("backup", stdout: CommandCatalog.Backups.controlDoneMarker)
        runner.stub("backup", stdout: "", exitCode: 1, stderr: "no such wrapper")

        do {
            try await AutoBackupOperations(runner: runner, deployment: deployment)
                .save(AutoBackupSettings(schedule: .days(count: 1, hour: 4, minute: 30), retention: 7, services: ["vaultwarden"]))
            XCTFail("a worker refused and the save reported success")
        } catch {
            XCTAssertEqual(runner.calls.count, 2)
        }
    }
}
