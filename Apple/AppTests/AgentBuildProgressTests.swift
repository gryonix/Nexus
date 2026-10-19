import XCTest
@testable import gryonixNexus

final class AgentBuildProgressTests: XCTestCase {
    private func steps(compiling count: Int, other: Int = 0) -> AgentBuildSteps {
        var steps = AgentBuildSteps()
        for index in 0..<count { steps.line("   Compiling crate\(index) v1.0.0") }
        for _ in 0..<other { steps.line("#7 [3/8] RUN apt-get update") }
        return steps
    }

    func testOnlyCompiledCratesMoveTheShare() {
        XCTAssertEqual(steps(compiling: 0, other: 300).fraction, 0)
        XCTAssertEqual(steps(compiling: AgentBuildSteps.crates / 2).fraction, 0.5, accuracy: 0.01)
    }

    func testTheShareStopsShortOfDoneUntilTheBuildEnds() {
        XCTAssertEqual(steps(compiling: 500).fraction, AgentBuildSteps.ceiling)
    }

    func testTheCrateCountMatchesTheAgentsLockFile() throws {
        let lock = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Server/gryonixnexusd/Cargo.lock")
        let text = try String(contentsOf: lock, encoding: .utf8)
        let names = text.components(separatedBy: "[[package]]\nname = \"").dropFirst()
            .compactMap { $0.split(separator: "\"").first.map(String.init) }
        let foreign = ["windows", "winapi", "wasi", "wasm", "js-sys", "web-sys", "hermit", "redox", "fuchsia"]
        let built = names.filter { name in !foreign.contains { name.hasPrefix($0) } }
        XCTAssertEqual(built.count, AgentBuildSteps.crates,
                       "the agent's dependencies changed; update AgentBuildSteps.crates")
    }
}
