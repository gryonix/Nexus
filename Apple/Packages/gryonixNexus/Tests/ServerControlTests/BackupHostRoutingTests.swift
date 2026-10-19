import ServiceCatalog
import XCTest
@testable import ServerControl

/// In a relay pair, backups belong to the home machine
final class BackupHostRoutingTests: XCTestCase {
    private func pair() -> Deployment {
        Deployment(name: "B", topology: .vpsRelayWithHomeBackend, domain: "example.com",
                   entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                   homeWGAddress: "10.8.0.2",
                   services: [.vaultwarden, .nextcloud])
    }

    private func hosts(of runner: FakeSSHCommandRunner) -> Set<SSHHostID> {
        Set(runner.calls.map(\.host))
    }

    func testTheHomeMachineIsTheOnlyWorkerOfAPair() {
        let deployment = pair()
        XCTAssertEqual(deployment.workerHosts, [deployment.servicesHost])
        XCTAssertNotEqual(deployment.servicesHost, .vps)
    }

    func testListingAndRunningBackupsAskTheHomeMachine() async throws {
        let deployment = pair()
        let runner = FakeSSHCommandRunner()
        let backups = SSHServiceBackups(runner: runner, deployment: deployment)
        let nextcloud = try XCTUnwrap(ServiceRegistry.service(.nextcloud))

        _ = try? await backups.listBackups(of: nextcloud)
        _ = try? await backups.estimate(of: nextcloud)
        _ = try? await backups.backup(nextcloud, encrypt: nil, passphrase: nil, onChunk: { _ in })

        XCTAssertFalse(runner.calls.isEmpty)
        XCTAssertEqual(hosts(of: runner), [deployment.servicesHost], "\(runner.calls)")
    }

    func testTheScheduleTheDestinationAndTheDrivesLiveOnTheHomeMachine() async {
        let deployment = pair()
        let runner = FakeSSHCommandRunner()
        let schedule = AutoBackupOperations(runner: runner, deployment: deployment)

        _ = try? await schedule.load()
        try? await schedule.save(AutoBackupSettings())
        _ = try? await schedule.loadDestination()
        _ = try? await schedule.loadDrives()
        try? await schedule.saveDrives(BackupDriveSettings())

        XCTAssertFalse(runner.calls.isEmpty)
        XCTAssertEqual(hosts(of: runner), [deployment.servicesHost], "\(runner.calls)")
    }

    // MARK: - One machine at home

    private func atHome(_ scope: DeploymentScope) -> Deployment {
        Deployment(name: "home", topology: .singleHost, domain: "example.com",
                   entry: HostEndpoint(host: "192.0.2.20", user: "admin"),
                   services: [.vaultwarden, .nextcloud], scope: scope)
    }

    func testEveryBackupCommandOfAHomeServerGoesToThatServer() async throws {
        for scope in [DeploymentScope.localOnly, .dynamicDNS] {
            let deployment = atHome(scope)
            let runner = FakeSSHCommandRunner()
            let nextcloud = try XCTUnwrap(ServiceRegistry.service(.nextcloud))
            let backups = SSHServiceBackups(runner: runner, deployment: deployment)
            let schedule = AutoBackupOperations(runner: runner, deployment: deployment)

            _ = try? await backups.listBackups(of: nextcloud)
            _ = try? await backups.backup(nextcloud, encrypt: nil, passphrase: nil, onChunk: { _ in })
            _ = try? await SSHServiceRestore(runner: runner, deployment: deployment)
                .restore(nextcloud, archivePath: "/opt/backups/nextcloud/a.tar.gz", passphrase: nil, onChunk: { _ in })
            _ = try? await schedule.load()
            _ = try? await schedule.loadDrives()

            XCTAssertFalse(runner.calls.isEmpty)
            XCTAssertEqual(hosts(of: runner), [deployment.servicesHost], "\(scope): \(runner.calls)")
            XCTAssertEqual(deployment.agentHosts, [deployment.servicesHost], "\(scope)")
            XCTAssertTrue(deployment.hasPhysicalAccess, "\(scope): USB drives are offered")
        }
    }
}
