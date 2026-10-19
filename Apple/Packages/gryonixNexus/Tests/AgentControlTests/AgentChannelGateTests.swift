import XCTest
@testable import AgentControl

final class AgentChannelGateTests: XCTestCase {
    /// Counts concurrent holders, remembering the peak
    private actor Peak {
        private(set) var current = 0
        private(set) var highest = 0

        func enter() { current += 1; highest = max(highest, current) }
        func leave() { current -= 1 }
    }

    func testNeverExceedsTheLimitUnderFanOut() async {
        let gate = AgentChannelGate(limit: 4)
        let peak = Peak()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<32 {
                group.addTask {
                    await gate.withSlot {
                        await peak.enter()
                        // Long enough that the tasks genuinely overlap.
                        try? await Task.sleep(nanoseconds: 2_000_000)
                        await peak.leave()
                    }
                }
            }
        }

        let highest = await peak.highest
        let current = await peak.current
        XCTAssertLessThanOrEqual(highest, 4, "more channels were open at once than sshd allows")
        XCTAssertGreaterThan(highest, 1, "the gate serialized everything — the fan-out was not real")
        XCTAssertEqual(current, 0, "a slot was leaked")
    }

    func testAThrowingBodyReleasesItsSlot() async {
        struct Boom: Error {}
        let gate = AgentChannelGate(limit: 1)

        for _ in 0..<3 {
            do {
                try await gate.withSlot { throw Boom() }
                XCTFail("expected the error to propagate")
            } catch is Boom {
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }

        // Still usable afterwards.
        let ran = await gate.withSlot { true }
        XCTAssertTrue(ran)
    }

    func testTheLimitIsTheSSHRunnersCeiling() {
        XCTAssertEqual(AgentChannelGate.defaultLimit, 4)
    }
}
