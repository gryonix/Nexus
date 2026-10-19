import MailRecipe
import XCTest

@testable import gryonixNexus

final class AgentBootstrapPathTests: XCTestCase {
    /// The refusal as the generated wrapper actually writes it
    private func refusal(user: String) -> String {
        let path = AgentBootstrapSections.archivePath(user: user)
        return "Agent bootstrap wrapper\nno agent sources uploaded (\(path))"
    }

    func testThePathIsReadBackOutOfTheWrappersOwnRefusal() {
        XCTAssertEqual(
            AgentBootstrapOperations.expectedArchivePath(in: refusal(user: "server-user")),
            "/home/server-user/gryonixnexus-agent-src.tar.gz")
    }

    /// The other account the generator can bake in
    func testARootInstallationIsReadTheSameWay() {
        XCTAssertEqual(
            AgentBootstrapOperations.expectedArchivePath(in: refusal(user: "root")),
            "/root/gryonixnexus-agent-src.tar.gz")
    }

    func testAnUnrelatedFailureYieldsNoPath() {
        XCTAssertNil(AgentBootstrapOperations.expectedArchivePath(
            in: "error: could not compile `gryonixnexusd`"))
        XCTAssertNil(AgentBootstrapOperations.expectedArchivePath(in: ""))
        XCTAssertNil(AgentBootstrapOperations.expectedArchivePath(
            in: "the uploaded archive carries no bootstrap script"))
    }

    func testOnlyAnAbsolutePathIsAccepted() {
        XCTAssertNil(AgentBootstrapOperations.expectedArchivePath(
            in: "no agent sources uploaded (relative/path.tar.gz)"))
        XCTAssertNil(AgentBootstrapOperations.expectedArchivePath(
            in: "no agent sources uploaded (/tmp/a b.tar.gz)"))
    }
}
