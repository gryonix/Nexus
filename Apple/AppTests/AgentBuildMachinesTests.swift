import XCTest
@testable import gryonixNexus

@MainActor
final class AgentBuildMachinesTests: XCTestCase {
    private func state() -> LongOperationState {
        LongOperationState(title: "Updating the agent", progressText: "")
    }

    func testOneMachineKeepsTheOldWords() {
        let run = state()
        let machines = AgentBuildMachines(state: run, names: ["VPS"])
        machines.started("VPS")
        machines.phase("Sending the agent sources…", of: "VPS")
        machines.output("Compiling serde v1", of: "VPS")
        XCTAssertEqual(run.progressText, "Sending the agent sources…")
        XCTAssertEqual(run.log, "Compiling serde v1\n")
    }

    func testSeveralMachinesNameEveryLine() {
        let run = state()
        let machines = AgentBuildMachines(state: run, names: ["VPS", "Local"])
        machines.started("VPS")
        machines.started("Local")
        machines.output("Compiling serde v1", of: "Local")
        machines.phase("Sending the agent sources…", of: "VPS")
        XCTAssertEqual(run.log, "Local: Compiling serde v1\nVPS: Sending the agent sources…\n")
    }

    func testTheSummarySaysWhichMachineIsStillBuilding() {
        let run = state()
        let machines = AgentBuildMachines(state: run, names: ["VPS", "Local"])
        let start = Date(timeIntervalSince1970: 1_000_000)
        machines.started("VPS", at: start)
        machines.started("Local", at: start)
        machines.finished("VPS", ok: true)
        let summary = machines.summary(now: start.addingTimeInterval(4 * 60 + 10))
        XCTAssertEqual(summary, "VPS: done · Local: building, 4 min")
        XCTAssertEqual(machines.summary(now: start.addingTimeInterval(20)), "VPS: done · Local: building")
    }

    func testProgressIsTheMeanOfTheMachines() {
        let run = state()
        let machines = AgentBuildMachines(state: run, names: ["VPS", "Local"])
        for _ in 0..<50 { machines.output("Compiling x", of: "VPS") }
        XCTAssertEqual(run.progress ?? 0, Double(50) / Double(AgentBuildSteps.crates) / 2, accuracy: 0.001)
    }
}
