import XCTest
import ServiceCatalog
@testable import ServerControl

final class InstalledDeploymentRecordTests: XCTestCase {
    private func stored() -> Deployment {
        var deployment = Deployment(
            name: "middle",
            topology: .singleHost,
            domain: "example.com",
            entry: HostEndpoint(host: "203.0.113.4", user: "server-user"),
            services: [.vaultwarden],
            usesAgent: true
        )
        deployment.tags = ["prod"]
        deployment.iconSymbol = "bolt"
        deployment.tintName = "teal"
        deployment.cardSize = .compact
        deployment.metricsIndicatorStyle = .rings
        deployment.timeouts = OperationTimeouts(quickSeconds: 42)
        deployment.wgInterface = "wg1"
        deployment.placement = ServicePlacement([ServiceID.vaultwarden.rawValue: UUID()])
        return deployment
    }

    private func generated(id: UUID) -> Deployment {
        Deployment(
            id: id,
            name: "example.com",
            topology: .singleHost,
            domain: "example.com",
            entry: HostEndpoint(host: "203.0.113.4", user: "server-user"),
            services: [.vaultwarden, .nextcloud]
        )
    }

    func testAReinstallKeepsTheAgentTheAppFound() {
        let existing = stored()
        let record = InstalledDeploymentRecord.merged(generated: generated(id: existing.id),
                                                      onto: existing)
        XCTAssertTrue(record.usesAgent,
                      "repairing a server made the app forget the daemon it manages it through")
    }

    func testAReinstallKeepsWhatTheFormNeverAskedAbout() {
        let existing = stored()
        let record = InstalledDeploymentRecord.merged(generated: generated(id: existing.id),
                                                      onto: existing)
        XCTAssertEqual(record.tags, ["prod"])
        XCTAssertEqual(record.iconSymbol, "bolt")
        XCTAssertEqual(record.tintName, "teal")
        XCTAssertEqual(record.cardSize, .compact)
        XCTAssertEqual(record.metricsIndicatorStyle, .rings)
        XCTAssertEqual(record.timeouts.quickSeconds, 42)
        XCTAssertEqual(record.wgInterface, "wg1")
        XCTAssertEqual(record.placement, existing.placement)
        XCTAssertEqual(record.storedNodes, existing.storedNodes)
    }

    func testAReinstallStillMovesWhatTheFormDoesOwn() {
        let existing = stored()
        var fresh = generated(id: existing.id)
        fresh.domain = "example.net"
        fresh.name = "example.net"
        fresh.entry = HostEndpoint(host: "203.0.113.9", user: "root")
        fresh.additionalDomains = ["alias.example.net"]
        fresh.usesPasswordAuth = true
        fresh.scope = .localOnly
        let record = InstalledDeploymentRecord.merged(generated: fresh, onto: existing)
        XCTAssertEqual(record.domain, "example.net")
        XCTAssertEqual(record.name, "example.net")
        XCTAssertEqual(record.entry.host, "203.0.113.9")
        XCTAssertEqual(record.entry.user, "root")
        XCTAssertEqual(record.additionalDomains, ["alias.example.net"])
        XCTAssertEqual(record.services, [.vaultwarden, .nextcloud])
        XCTAssertTrue(record.usesPasswordAuth)
        XCTAssertEqual(record.scope, .localOnly)
    }

    func testAFirstInstallIsStoredExactlyAsGenerated() {
        let fresh = generated(id: UUID())
        XCTAssertEqual(InstalledDeploymentRecord.merged(generated: fresh, onto: nil), fresh)
    }

    /// The nodes of a deployment that grew a third machine
    func testAThirdMachineSurvivesAReinstall() {
        var existing = stored()
        let extra = DeploymentNode(id: UUID(), name: "worker",
                                   endpoint: HostEndpoint(host: "10.8.0.3", user: "server-user"),
                                   capabilities: [.worker])
        existing.storedNodes = existing.nodes + [extra]
        let record = InstalledDeploymentRecord.merged(generated: generated(id: existing.id),
                                                      onto: existing)
        XCTAssertEqual(record.storedNodes?.count, existing.storedNodes?.count)
        XCTAssertEqual(record.nodes.count, existing.nodes.count)
    }
}
