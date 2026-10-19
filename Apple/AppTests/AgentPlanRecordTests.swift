import ServiceCatalog
import XCTest
@testable import gryonixNexus

final class AgentPlanRecordTests: XCTestCase {
    func testAPlanTheAppClosedOnComesBackWithItsSteps() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AgentPlanRecordTests"))
        defaults.removePersistentDomain(forName: "AgentPlanRecordTests")
        let server = UUID()
        let steps = ServiceInstallPlan.steps(for: [.nextcloud, .amneziaWG, .xrayReality].compactMap(ServiceRegistry.service),
                                             installed: [])
        AgentPlanRecord.remember(planID: "plan-7", steps: steps, deployment: server, defaults: defaults)

        let back = try XCTUnwrap(AgentPlanRecord.stored(deployment: server, defaults: defaults))
        XCTAssertEqual(back.planID, "plan-7")
        XCTAssertEqual(back.steps.map(\.service.id), [.nextcloud, .amneziaWG])
        XCTAssertEqual(back.steps.last?.alsoProtocols, [.xrayReality])

        AgentPlanRecord.forget(deployment: server, defaults: defaults)
        XCTAssertNil(AgentPlanRecord.stored(deployment: server, defaults: defaults))
    }
}
