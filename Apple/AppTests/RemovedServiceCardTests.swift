import ServerControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

@MainActor
final class RemovedServiceCardTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await DemoFleetState.shared.forgetEverything()
    }

    func testRemovingAServiceTakesItsCardOffTheScreenAtOnce() async throws {
        let deployment = DemoServer.sshOnly()
        let service = try XCTUnwrap(ServiceRegistry.service(.forgejo))
        let model = DashboardViewModel(deployment: deployment,
                                       makeRunner: { DemoCommandRunner(deployment: $0) })
        XCTAssertTrue(model.services.contains { $0.id == .forgejo },
                      "the fixture has to start with the service on screen")

        let updated = await model.uninstall(service, purge: .none)

        XCTAssertNotNil(updated, "the demo server accepts the removal")
        XCTAssertFalse(model.services.contains { $0.id == .forgejo },
                       "the card must go with the service")
        XCTAssertFalse(model.deployment.services.contains(.forgejo))
        XCTAssertEqual(updated?.services.contains(.forgejo), false)
    }
}
