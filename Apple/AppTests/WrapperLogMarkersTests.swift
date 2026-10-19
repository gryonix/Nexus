import ServerControl
import ServiceCatalog
import XCTest

@testable import gryonixNexus

@MainActor
final class WrapperLogMarkersTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await DemoFleetState.shared.forgetEverything()
    }

    func testTheUpdatePaneDropsTheWrappersProtocolMarkers() async throws {
        let deployment = DemoServer.sshOnly()
        let service = try XCTUnwrap(ServiceRegistry.service(.forgejo))
        let model = DashboardViewModel(deployment: deployment,
                                       makeRunner: { DemoCommandRunner(deployment: $0) })

        await model.runUpdateNow(service)

        let operation = try XCTUnwrap(RunningOperationsRegistry.shared.presented,
                                      "the update presents its progress sheet")
        for line in operation.log.split(separator: "\n", omittingEmptySubsequences: false) {
            XCTAssertFalse(WrapperLogText.isProtocol(String(line)),
                           "a wrapper's protocol marker reached the pane: \(line)")
        }
    }
}
