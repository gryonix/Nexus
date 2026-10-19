import ServiceCatalog
import XCTest
@testable import ServerControl

final class ServiceControlRoutingTests: XCTestCase {
    private func deployment(usesAgent: Bool = false) -> Deployment {
        Deployment(
            name: "Test",
            topology: .singleHost,
            domain: "example.com",
            entry: HostEndpoint(host: "203.0.113.4", user: "admin"),
            services: [.nextcloud],
            usesAgent: usesAgent
        )
    }

    private func service(_ id: ServiceID) throws -> any ManagedService {
        try XCTUnwrap(ServiceRegistry.service(id))
    }

    func testADeploymentIsOnSSHUnlessItExplicitlyHasAnAgent() {
        XCTAssertFalse(deployment().usesAgent)
        XCTAssertEqual(
            ServiceControlRouting.route(usesAgent: deployment().usesAgent, agentTransportAvailable: true),
            .ssh)
        XCTAssertEqual(
            ServiceControlRouting.route(usesAgent: deployment(usesAgent: true).usesAgent,
                                        agentTransportAvailable: true),
            .agent)
        XCTAssertEqual(
            ServiceControlRouting.route(usesAgent: true, agentTransportAvailable: false),
            .ssh)
    }

    func testSSHRouteSendsTheSameCatalogCommandsAsBefore() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("docker compose -p nextcloud restart")
        runner.stub("docker compose -p nextcloud ps", stdout: """
        NAME            IMAGE             COMMAND    SERVICE   CREATED       STATUS         PORTS
        nextcloud-app   nextcloud:apache  "apache"   app       2 hours ago   Up 2 hours     127.0.0.1:8081->80/tcp
        """)
        let control = SSHServiceControl(runner: runner, deployment: deployment())

        let statuses = try await control.power(.restart, on: try service(.nextcloud))

        XCTAssertEqual(statuses.map(\.name), ["nextcloud-app"])
        XCTAssertEqual(runner.calls.map(\.command), [
            "sudo docker compose -p nextcloud restart",
            "sudo docker compose -p nextcloud ps"
        ])
        XCTAssertTrue(runner.calls.allSatisfy { $0.host == .vps })
    }

    func testSSHRouteStartAndStopUseTheirOwnVerbsAndNeverDown() async throws {
        for (action, verb) in [(ServicePowerAction.start, "start"), (.stop, "stop")] {
            let runner = FakeSSHCommandRunner()
            runner.stub("docker compose -p nextcloud \(verb)")
            runner.stub("docker compose -p nextcloud ps", stdout: """
            NAME            IMAGE   COMMAND   SERVICE   CREATED   STATUS       PORTS
            nextcloud-app   img     "x"       app       now       Up 1 minute  80/tcp
            """)
            let control = SSHServiceControl(runner: runner, deployment: deployment())

            _ = try await control.power(action, on: try service(.nextcloud))

            XCTAssertEqual(runner.calls.first?.command, "sudo docker compose -p nextcloud \(verb)")
            XCTAssertFalse(runner.calls.contains { $0.command.contains(" down") },
                           "stopping a service must never remove its containers")
        }
    }

    func testSSHRouteStatusIsTheUnchangedProbe() async throws {
        let runner = FakeSSHCommandRunner()
        runner.stub("docker compose -p nextcloud ps", stdout: """
        NAME            IMAGE   COMMAND   SERVICE   CREATED   STATUS                PORTS
        nextcloud-app   img     "x"       app       now       Exited (0) 1 min ago
        """)
        let control = SSHServiceControl(runner: runner, deployment: deployment())

        let statuses = try await control.status(of: try service(.nextcloud))

        XCTAssertEqual(statuses.map(\.health), [.critical])
        XCTAssertEqual(runner.calls.map(\.command), ["sudo docker compose -p nextcloud ps"])
    }
}
