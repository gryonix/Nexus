import AgentControl
import ServerControl
import XCTest

@testable import gryonixNexus

/// A tapped alert finds its run and opens its window
@MainActor
final class RunOpeningTests: XCTestCase {
    private func job(_ id: String, running: Bool) -> AgentJob {
        AgentJob(id: id, kind: .update, subject: "nextcloud", started: Date(),
                 finished: running ? nil : Date(), outcome: running ? .running : .failed,
                 failure: running ? "" : "pull failed", events: 3)
    }

    func testTheRunIsFoundByItsIdWhetherItStillRunsOrHasEnded() {
        let listed = [job("job-1", running: true), job("job-2", running: false)]
        XCTAssertEqual(RunningJobsWatcher.job(named: "job-2", among: listed)?.id, "job-2")
        XCTAssertEqual(RunningJobsWatcher.job(named: "job-1", among: listed)?.id, "job-1")
        XCTAssertNil(RunningJobsWatcher.job(named: "job-3", among: listed), "a run the server forgot")
        XCTAssertNil(RunningJobsWatcher.job(named: "job-1", among: []))
    }

    func testAWindowThatFollowsTheRunIsBroughtUpByItsId() {
        let registry = RunningOperationsRegistry.shared
        let state = LongOperationState(title: "Updating Nextcloud")
        registry.adopt(state, jobID: "run-opening-job", onLockScreen: false)
        defer {
            state.isFinished = true
            registry.dismiss(state.id)
            registry.presented = nil
        }
        XCTAssertTrue(registry.holds(jobID: "run-opening-job"))
        XCTAssertTrue(registry.present(jobID: "run-opening-job"))
        XCTAssertTrue(registry.presented === state)
    }

    func testAnUnknownRunOpensNothing() {
        let registry = RunningOperationsRegistry.shared
        let before = registry.presented
        XCTAssertFalse(registry.present(jobID: "no-such-run"))
        XCTAssertTrue(registry.presented === before)
    }
}
