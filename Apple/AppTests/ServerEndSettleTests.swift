import AgentControl
import XCTest
@testable import gryonixNexus

@MainActor
final class ServerEndSettleTests: XCTestCase {
    private func job(_ outcome: AgentJobOutcome, failure: String = "") -> AgentJob {
        AgentJob(id: "6ac4199b-8dc75-1", kind: .update, subject: "immich", started: Date(),
                 finished: Date(), outcome: outcome, failure: failure, events: 12)
    }

    func testAServerSuccessClosesTheRunAndALateStreamErrorCannotUndoIt() {
        let state = LongOperationState(title: "Updating Immich", progressText: "Pulling images")
        RunningJobsWatcher.settle(state, with: job(.succeeded))
        XCTAssertTrue(state.isFinished)
        XCTAssertNil(state.errorMessage)
        state.errorMessage = "the connection was lost"
        state.progressText = "Pulling images"
        XCTAssertNil(state.errorMessage, "the server's ending stays")
        XCTAssertEqual(state.progressText, UIL10n.string("Done"))
    }

    func testAServerFailureCarriesItsReason() {
        let state = LongOperationState(title: "Updating Immich")
        RunningJobsWatcher.settle(state, with: job(.failed, failure: "image pull failed"))
        XCTAssertTrue(state.isFinished)
        XCTAssertEqual(state.errorMessage, "image pull failed")
    }

    func testARunThatAlreadyEndedIsLeftAlone() {
        let state = LongOperationState(title: "Updating Immich")
        state.errorMessage = "stopped by the user"
        state.isFinished = true
        RunningJobsWatcher.settle(state, with: job(.succeeded))
        XCTAssertEqual(state.errorMessage, "stopped by the user")
    }
}
