import AgentControl
import XCTest

@testable import gryonixNexus

/// What the install screen makes of an agent's plan
@available(macOS 15.0, *)
final class InstallPlanFollowerTests: XCTestCase {
    private func plan(_ items: [AgentInstallPlan.Item], finished: Bool = true) -> AgentInstallPlan {
        AgentInstallPlan(id: "p1", items: items, finished: finished)
    }

    func testFailedAndSkippedServicesAreNamedForTheOwner() {
        let ended = plan([
            .init(agentServiceID: "vaultwarden", state: .done, jobID: "j1"),
            .init(agentServiceID: "vpn", state: .failed, failure: "ports in use"),
            .init(agentServiceID: "immich", state: .skipped),
        ])
        let message = InstallPlanFollower.failureMessage(ended) ?? ""
        XCTAssertTrue(message.contains("VPN"), message)
        XCTAssertTrue(message.contains("Immich"), message)
        XCTAssertFalse(message.contains("Vaultwarden"), message)
        XCTAssertNil(InstallPlanFollower.failureMessage(plan([.init(agentServiceID: "immich", state: .done)])))
    }

    func testTheAgentsStepMarkerNamesNumberTotalAndService() {
        let step = InstallPlanFollower.step("GRYONIXNEXUS_STEP 2/5\nnextcloud")
        XCTAssertEqual(step?.index, 2)
        XCTAssertEqual(step?.total, 5)
        XCTAssertEqual(step?.service, "nextcloud")
        XCTAssertNil(InstallPlanFollower.step("pulling the Nextcloud images"))
        XCTAssertNil(InstallPlanFollower.step("GRYONIXNEXUS_STEP broken"))
    }

    func testTheLogMarkRemembersWhereReadingStopped() {
        let mark = PlanLogMark()
        XCTAssertEqual(mark.next, 0)
        mark.next = 41
        XCTAssertEqual(mark.next, 41)
    }

    func testAMailServerThatCameUpAsksForItsDKIMRecords() {
        XCTAssertTrue(InstallPlanFollower.installedMail(plan([.init(agentServiceID: "mailcow", state: .done)])))
        XCTAssertFalse(InstallPlanFollower.installedMail(plan([.init(agentServiceID: "mailcow", state: .failed)])))
    }
}
