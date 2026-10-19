import ServerControl
import XCTest

@testable import gryonixNexus

@MainActor
final class SecurityCardAnswerTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await DemoFleetState.shared.forgetEverything()
    }

    func testAnAgentThatCannotAnswerLeavesTheCardSayingSoRatherThanSpinning() async {
        // Not the demo server, which is seeded with a defence
        var deployment = Deployment(name: "adopted",
                                    topology: .singleHost,
                                    domain: "example.com",
                                    entry: HostEndpoint(host: "203.0.113.10", user: "root"),
                                    services: [.vaultwarden])
        deployment.usesAgent = true
        let model = DashboardViewModel(deployment: deployment,
                                       makeRunner: { DemoCommandRunner(deployment: $0) })
        XCTAssertNil(model.securityStatus, "precondition: nothing has been asked yet")

        await model.loadSecurity()

        XCTAssertNotNil(model.securityStatus,
                        "nil is the spinner, and the row that would ask again is gone once it draws")
        XCTAssertEqual(model.securityStatus?.isPresent, false,
                       "the card reads this as \"Not set up\", which is the honest answer")
    }

    func testAServerWithoutAnAgentIsNotAskedAndKeepsNoStatus() async {
        let model = DashboardViewModel(deployment: DemoServer.sshOnly(),
                                       makeRunner: { DemoCommandRunner(deployment: $0) })
        XCTAssertFalse(model.canShowSecurity)

        await model.loadSecurity()

        XCTAssertNil(model.securityStatus)
    }

    func testTheUnknownStatusClaimsNothing() {
        let unknown = HostSecurityStatus.unknown
        XCTAssertFalse(unknown.isPresent)
        XCTAssertFalse(unknown.isHealthy)
        XCTAssertEqual(unknown.alertsLast24h, 0)
        XCTAssertEqual(unknown.localBans, 0)
        XCTAssertEqual(unknown.communityBlocklistIPs, 0)
        XCTAssertTrue(unknown.recentBans.isEmpty)
    }
}
