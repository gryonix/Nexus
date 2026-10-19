import AgentClient
import AgentControl
import XCTest

@testable import gryonixNexus

@available(macOS 15.0, *)
final class ContainerUpdateOfferTests: XCTestCase {
    private let emptyPlan = AgentError.rpc(
        code: "failed_precondition",
        message: "nothing_to_archive: this group stores nothing outside its images")

    func testTheEmptyPlanRefusalIsOfferedTheSkip() {
        XCTAssertTrue(ContainerUpdateOffer.mayUpdateWithoutBackup(
            kind: .update, alreadySkipped: false, error: emptyPlan))
    }

    func testAPlanWhoseSourcesAreGoneIsNotOfferedTheSkip() {
        let stale = AgentError.rpc(
            code: "internal",
            message: "this plan names nothing that exists on the host — nothing was archived")
        XCTAssertFalse(ContainerUpdateOffer.mayUpdateWithoutBackup(
            kind: .update, alreadySkipped: false, error: stale))
    }

    /// A backup has no backup to skip
    func testABackupIsNeverOfferedTheSkip() {
        XCTAssertFalse(ContainerUpdateOffer.mayUpdateWithoutBackup(
            kind: .backup, alreadySkipped: false, error: emptyPlan))
    }

    func testARunThatAlreadySkippedIsNotOfferedItAgain() {
        XCTAssertFalse(ContainerUpdateOffer.mayUpdateWithoutBackup(
            kind: .update, alreadySkipped: true, error: emptyPlan))
    }

    /// Every other failure
    func testNothingElseIsMistakenForIt() {
        XCTAssertFalse(ContainerUpdateOffer.mayUpdateWithoutBackup(
            kind: .update, alreadySkipped: false,
            error: AgentError.transport("the agent bridge did not start: Connection refused")))
        XCTAssertFalse(ContainerUpdateOffer.mayUpdateWithoutBackup(
            kind: .update, alreadySkipped: false,
            error: AgentError.rpc(code: "failed_precondition",
                                  message: "this group has a database that would be dumped")))
    }
}
