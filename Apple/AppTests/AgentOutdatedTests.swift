import AgentClient
import XCTest

@testable import gryonixNexus

final class AgentOutdatedTests: XCTestCase {
    func testAnOldAgentsDiskReplyAsksForAnUpdate() {
        let error = AgentError.rpc(code: "invalid_argument", message: "choose a disk task")
        XCTAssertTrue(AgentOutdated.matches(error))
        XCTAssertFalse(AgentOutdated.describe(error).contains("rpc("))
    }

    func testOtherAgentErrorsReadAsTheirOwnMessage() {
        let error = AgentError.rpc(code: "failed_precondition", message: "the disk is mounted")
        XCTAssertFalse(AgentOutdated.matches(error))
        XCTAssertEqual(AgentOutdated.describe(error), "the disk is mounted")
    }

    func testKnownWrapperLinesBecomeStagesAndOthersDoNot() {
        XCTAssertNotNil(WrapperLogText.headline("backing up nextcloud before updating it"))
        XCTAssertNotNil(WrapperLogText.headline("waiting for immich: server"))
        XCTAssertNil(WrapperLogText.headline("Pulling fs layer"))
    }
}
