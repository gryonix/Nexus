import AgentClient
import XCTest

@testable import gryonixNexus

@MainActor
final class StopRefusalTests: XCTestCase {
    func testAStepThatCannotStopIsToldApart() {
        let refusal = AgentError.rpc(code: "failed_precondition", message: "this run cannot be stopped once it has started")
        XCTAssertEqual(StopRefusal.reason(of: refusal),
                       UIL10n.string("The server can't stop this step once it has started."))
    }

    func testOtherFailuresCarryTheirText() {
        let reason = StopRefusal.reason(of: AgentError.transport("connection reset"))
        XCTAssertTrue(reason.contains("connection reset"))
    }

    func testAMissingRunIsSaidPlainly() {
        XCTAssertEqual(StopRefusal.reason(of: StopMiss.nothingRunning),
                       UIL10n.string("The server is no longer running this."))
        XCTAssertEqual(StopRefusal.reason(of: StopMiss.serverGone),
                       UIL10n.string("This server is no longer in the app."))
    }
}
