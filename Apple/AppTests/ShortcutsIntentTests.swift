import ServerControl
import ServiceCatalog
import VPNTunnel
import XCTest
@testable import gryonixNexus

@MainActor
final class ShortcutsIntentTests: XCTestCase {
    private func deployment(_ name: String, services: Set<ServiceID>) -> Deployment {
        Deployment(name: name, topology: .singleHost, domain: "\(name).example.com",
                   entry: HostEndpoint(host: "203.0.113.9", user: "root"), services: services)
    }

    func testServerEntitiesCarryEveryServersNameAndId() {
        let a = deployment("alpha", services: [.forgejo])
        let b = deployment("beta", services: [])
        let entities = ServerEntity.all(in: [a, b])
        XCTAssertEqual(entities.map(\.name), ["alpha", "beta"])
        XCTAssertEqual(entities.map(\.id), [a.id, b.id])
    }

    func testServiceEntitiesNameTheirServer() {
        let a = deployment("alpha", services: [.forgejo, .vaultwarden])
        let entities = ServiceEntity.all(in: [a])
        XCTAssertEqual(Set(entities.map(\.serviceID)), ["forgejo", "vaultwarden"])
        XCTAssertTrue(entities.allSatisfy { $0.serverName == "alpha" && $0.serverID == a.id })
    }

    func testAServiceEntityResolvesBackToItsDeploymentAndService() throws {
        let a = deployment("alpha", services: [.forgejo])
        let entity = try XCTUnwrap(ServiceEntity.all(in: [a]).first)
        let resolved = try XCTUnwrap(ServiceEntity.resolve(entity, in: [a]))
        XCTAssertEqual(resolved.0.id, a.id)
        XCTAssertEqual(resolved.1.id, .forgejo)
        XCTAssertNil(ServiceEntity.resolve(entity, in: []))
    }

    func testTheQueryFindsServersByNameIgnoringCase() async throws {
        let a = deployment("Alpha", services: [])
        IntentFleet.loadDeployments = { [a] }
        let found = try await ServerEntityQuery().entities(matching: "alp")
        XCTAssertEqual(found.map(\.id), [a.id])
        let none = try await ServerEntityQuery().entities(matching: "zzz")
        XCTAssertTrue(none.isEmpty)
    }

    func testStatusReportStates() {
        XCTAssertEqual(ServerStatusReport(name: "x", server: nil).state, .unknown)
        let down = FleetSnapshot.Server(id: UUID(), name: "x", failure: "timeout")
        XCTAssertEqual(ServerStatusReport(name: "x", server: down).state, .offline)
        let up = FleetSnapshot.Server(
            id: UUID(), name: "x",
            metrics: .init(cpuPercent: 40, memUsedBytes: 50, memTotalBytes: 100,
                           diskUsedBytes: 10, diskTotalBytes: 100, machineLabel: "m", takenAt: Date()),
            services: .init(total: 4, needingAttention: 2, takenAt: Date()))
        let report = ServerStatusReport(name: "x", server: up)
        XCTAssertEqual(report.state, .online)
        XCTAssertEqual(report.memory, 50)
        XCTAssertEqual(report.disk, 10)
        XCTAssertEqual(report.problems, 2)
        XCTAssertTrue(report.sentence.contains("40%"))
    }

    func testPowerRunnerRefusesAServiceThatIsGone() async {
        let gone = ServiceEntity(id: "a/b", serverID: UUID(), serviceID: "forgejo",
                                 name: "Forgejo", serverName: "alpha")
        do {
            _ = try await ServicePowerRunner.run(.restart, on: gone, deployments: [])
            XCTFail("expected a failure")
        } catch {
            XCTAssertTrue(error is IntentFailure)
        }
    }

    func testPowerRunnerReportsAConnectionFailureAsAnError() async throws {
        let a = deployment("alpha", services: [.forgejo])
        let entity = try XCTUnwrap(ServiceEntity.all(in: [a]).first)
        struct Boom: Error {}
        do {
            _ = try await ServicePowerRunner.run(
                .restart, on: entity, deployments: [a],
                makeModel: { DashboardViewModel(deployment: $0, makeRunner: { _ in throw Boom() }) })
            XCTFail("expected a failure")
        } catch {
            XCTAssertTrue(error is IntentFailure)
        }
    }
}
