import XCTest
import ServerControl

@testable import gryonixNexus

@available(macOS 15.0, *)
final class AgentAdoptionFailureTests: XCTestCase {
    func testARefusedKeyIsClassifiedAsARefusedKey() {
        let failure = AgentAdoption.Failure.fromConnection(
            ServerControlError.connectionFailed("allAuthenticationOptionsFailed"))
        guard case .keyRefused = failure else {
            return XCTFail("an authentication failure must not be reported as anything else")
        }
    }

    func testTheSpelledOutFormIsCaughtToo() {
        let failure = AgentAdoption.Failure.fromConnection(
            ServerControlError.connectionFailed("SSH authentication failed for user root"))
        guard case .keyRefused = failure else {
            return XCTFail("\"authentication failed\" is a refused key")
        }
    }

    func testADeadHostIsNotBlamedOnTheKey() {
        let failure = AgentAdoption.Failure.fromConnection(
            ServerControlError.connectionFailed("connection refused"))
        guard case .unreachable = failure else {
            return XCTFail("a connection that never opened is not an authentication problem")
        }
    }

    func testTheGenuinelyAbsentAgentKeepsItsOwnAnswer() {
        let failure = AgentAdoption.Failure.noAgent("bridge exited: command not found")
        guard case .noAgent = failure else { return XCTFail("unexpected reclassification") }
        XCTAssertEqual(failure.errorDescription, "bridge exited: command not found",
                       "the transport's own words are the only evidence there is")
    }

    func testEveryFailureCarriesItsDetail() {
        let cases: [AgentAdoption.Failure] = [
            .unreachable("no route to host"),
            .keyRefused("allAuthenticationOptionsFailed"),
            .noAgent("nothing spoke back"),
            .agentFailed("pairing code rejected")
        ]
        for failure in cases {
            XCTAssertFalse(failure.errorDescription?.isEmpty ?? true)
        }
    }
}
