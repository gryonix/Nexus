import XCTest
import ServiceCatalog
@testable import ServerControl

/// Where updates and removals are performed, decided before anything runs
final class ServiceUpdateRoutingTests: XCTestCase {
    func testUpdatesGoThroughTheAgentOnlyWhenTheDeploymentHasOneAndThisDeviceCanReachIt() {
        XCTAssertEqual(ServiceUpdateRouting.route(usesAgent: true, agentTransportAvailable: true), .agent)
        XCTAssertEqual(ServiceUpdateRouting.route(usesAgent: true, agentTransportAvailable: false), .ssh,
                       "an OS below the exec-bridge gate keeps updates rather than losing them")
        XCTAssertEqual(ServiceUpdateRouting.route(usesAgent: false, agentTransportAvailable: true), .ssh,
                       "a deployment without an agent must behave exactly as it did before")
        XCTAssertEqual(ServiceUpdateRouting.route(usesAgent: false, agentTransportAvailable: false), .ssh)
    }

    func testRemovingOneServiceCanGoThroughTheAgent() {
        XCTAssertEqual(ServiceRemovalRouting.route(scope: .service, usesAgent: true,
                                                   agentTransportAvailable: true), .agent)
        XCTAssertEqual(ServiceRemovalRouting.route(scope: .service, usesAgent: false,
                                                   agentTransportAvailable: true), .ssh)
    }

    func testErasingEverythingNeverGoesThroughTheAgent() {
        for usesAgent in [true, false] {
            for reachable in [true, false] {
                XCTAssertEqual(ServiceRemovalRouting.route(scope: .everything, usesAgent: usesAgent,
                                                           agentTransportAvailable: reachable),
                               .ssh,
                               "erase must stay on the transport that outlives its own subject "
                                 + "(usesAgent: \(usesAgent), reachable: \(reachable))")
            }
        }
    }
}

final class ServiceUpdateAndRemovalSeamTests: XCTestCase {
    private func deployment(services: Set<ServiceID> = [.nextcloud]) -> Deployment {
        Deployment(
            name: "Test",
            topology: .singleHost,
            domain: "example.com",
            entry: HostEndpoint(host: "203.0.113.4", user: "admin"),
            services: services
        )
    }

    func testRunReportsAnUpdatedServiceFromTheStreamedMarker() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("gryonixnexus-update-ctl.sh run",
                    stdout: "Backing up nextcloud…\nGRYONIXNEXUS_UPDATE_DONE nextcloud\n")
        let ops: any ServiceUpdateManaging = ServiceUpdateOperations(runner: runner, deployment: deployment())
        let record = try await ops.run(.nextcloud, onChunk: { _ in })
        XCTAssertEqual(record, ServiceUpdateRunRecord(service: .nextcloud, outcome: .updated))
        let launch = runner.calls.first?.command ?? ""
        XCTAssertTrue(launch.contains("sudo /opt/gryonixnexus-update-ctl.sh run"), launch)
        XCTAssertTrue(launch.contains("nextcloud"), launch)
        XCTAssertEqual(runner.calls.first?.kind, .run, "the launch returns at once")
        XCTAssertTrue(runner.calls.contains { $0.kind == .stream },
                      "and the app follows the job's log afterwards")
    }

    func testRunReportsARollback() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("gryonixnexus-update-ctl.sh run",
                    stdout: "GRYONIXNEXUS_UPDATE_ROLLED_BACK nextcloud a container is still starting\n")
        let ops = ServiceUpdateOperations(runner: runner, deployment: deployment())
        let record = try await ops.run(.nextcloud)
        XCTAssertEqual(record, ServiceUpdateRunRecord(
            service: .nextcloud, outcome: .rolledBack(reason: "a container is still starting")))
    }

    func testRunWithoutAMarkerThrows() async {
        let runner = FakeSSHCommandRunner()
        runner.stub("gryonixnexus-update-ctl.sh run", stdout: "this service manages its own updates\n")
        let ops = ServiceUpdateOperations(runner: runner, deployment: deployment())
        do {
            _ = try await ops.run(.nextcloud)
            XCTFail("expected commandFailed")
        } catch {
            guard case ServerControlError.commandFailed = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    // MARK: - Removal: SSHServiceRemoval

    func testSSHServiceRemovalRunsTheWrapperAndChecksTheMarker() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("gryonixnexus-uninstall.sh", stdout: "removing containers...\nGRYONIXNEXUS_UNINSTALL_DONE\n")
        let seam: any ServiceRemovalManaging = SSHServiceRemoval(runner: runner, deployment: deployment())
        let service = try XCTUnwrap(ServiceRegistry.service(.nextcloud))
        _ = try await seam.remove(service, purge: .none, onChunk: { _ in })
        XCTAssertTrue(runner.calls.first?.command.contains(
            "sudo /opt/gryonixnexus-uninstall.sh nextcloud") == true,
            runner.calls.first?.command ?? "")
        XCTAssertEqual(runner.calls.first?.kind, .run)
    }

    func testSSHServiceRemovalForwardsPurgeOptions() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("", stdout: "GRYONIXNEXUS_UNINSTALL_DONE\n")
        let seam = SSHServiceRemoval(runner: runner, deployment: deployment())
        let service = try XCTUnwrap(ServiceRegistry.service(.nextcloud))
        _ = try await seam.remove(service, purge: PurgeOptions(data: true, backups: true), onChunk: { _ in })
        XCTAssertTrue(runner.calls.first?.command.contains(
            "sudo /opt/gryonixnexus-uninstall.sh nextcloud --purge-data --purge-backups") == true,
            runner.calls.first?.command ?? "")
    }

    func testSSHServiceRemovalWithoutMarkerThrows() async {
        let runner = FakeSSHCommandRunner()
        runner.stub("", stdout: "removing containers...\n")
        let seam = SSHServiceRemoval(runner: runner, deployment: deployment())
        do {
            let service = try XCTUnwrap(ServiceRegistry.service(.nextcloud))
            _ = try await seam.remove(service, purge: .none, onChunk: { _ in })
            XCTFail("expected commandFailed")
        } catch {
            guard case ServerControlError.commandFailed = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }
}
