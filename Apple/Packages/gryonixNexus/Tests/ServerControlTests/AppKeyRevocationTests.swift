import Foundation
@testable import ServerControl
import XCTest

final class AppKeyRevocationTests: XCTestCase {
    private let key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyBodyForTests0123456789 gryonixnexus"

    func testTheKeyBodyIsTheSecondField() {
        XCTAssertEqual(AppKeyRevocation.keyBody(of: key), "AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyBodyForTests0123456789")
    }

    func testAnythingThatCouldBreakTheQuotingIsRefused() {
        XCTAssertNil(AppKeyRevocation.keyBody(of: "ssh-ed25519 AAAA'; rm -rf ~ #0123456789"))
        XCTAssertNil(AppKeyRevocation.keyBody(of: "ssh-ed25519"))
        XCTAssertNil(AppKeyRevocation.keyBody(of: ""))
    }

    func testOnlyKeyAndNoPasswordIsTheLastWayIn() throws {
        let check = try XCTUnwrap(AppKeyRevocation.parse("present=yes\nothers=0\npassword=no\n"))
        XCTAssertTrue(check.isLastWayIn)
    }

    func testAnUnreadablePasswordSettingCountsAsNoWayIn() throws {
        let check = try XCTUnwrap(AppKeyRevocation.parse("present=yes\nothers=0\npassword=unknown"))
        XCTAssertNil(check.passwordLogin)
        XCTAssertTrue(check.isLastWayIn)
    }

    func testAnotherKeyOrPasswordLoginLeavesAWayIn() throws {
        XCTAssertFalse(try XCTUnwrap(AppKeyRevocation.parse("present=yes\nothers=2\npassword=no")).isLastWayIn)
        XCTAssertFalse(try XCTUnwrap(AppKeyRevocation.parse("present=yes\nothers=0\npassword=yes")).isLastWayIn)
    }

    func testAMissingKeyIsNeverTheLastWayIn() throws {
        XCTAssertFalse(try XCTUnwrap(AppKeyRevocation.parse("present=no\nothers=0\npassword=no")).isLastWayIn)
    }

    func testAnUnrelatedAnswerIsNotACheck() {
        XCTAssertNil(AppKeyRevocation.parse("bash: line 1: grep: command not found"))
    }

    func testTheScriptsCarryOnlyTheQuotedBody() throws {
        let body = try XCTUnwrap(AppKeyRevocation.keyBody(of: key))
        let remove = AppKeyRevocation.removeScript(keyBody: body)
        XCTAssertTrue(remove.contains("grep -vF '\(body)'"), remove)
        XCTAssertTrue(remove.contains("chmod 600"), remove)
        XCTAssertFalse(remove.contains("gryonixnexus"), "the comment field never reaches the shell")
        XCTAssertTrue(AppKeyRevocation.checkScript(keyBody: body).contains("passwordauthentication"))
    }

    func testMachinesBehindOthersAreHandledFirst() {
        let entry = DeploymentNode(id: UUID(), name: "orion", endpoint: HostEndpoint(host: "203.0.113.4", user: "ops"),
                                   capabilities: [.ingress])
        let middle = DeploymentNode(id: UUID(), name: "draco", endpoint: HostEndpoint(host: "10.0.0.2", user: "ops"),
                                    capabilities: [.worker], routedThrough: entry.id)
        let deep = DeploymentNode(id: UUID(), name: "lyra", endpoint: HostEndpoint(host: "10.0.0.3", user: "ops"),
                                  capabilities: [.worker], routedThrough: middle.id)
        let order = AppKeyRevocation.removalOrder([entry, middle, deep]).map(\.name)
        XCTAssertEqual(order, ["lyra", "draco", "orion"])
    }
}
