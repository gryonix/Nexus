import AgentClient
import Foundation
import ServerControl
import ServiceCatalog
import SwiftProtobuf
import XCTest
@testable import AgentControl

private struct MailMockTransport: AgentTransport {
    var onUnary: @Sendable (String, Data) async throws -> Data = { _, _ in Data() }

    func unary(path: String, request: Data) async throws -> Data {
        try await onUnary(path, request)
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private func listing(_ rows: [(String, String)]) throws -> Data {
    var list = Gryonixnexusd_V1_MailboxList()
    list.mailboxes = rows.map { address, detail in
        var mailbox = Gryonixnexusd_V1_Mailbox()
        mailbox.address = address
        mailbox.detail = detail
        mailbox.manageable = true
        return mailbox
    }
    return try list.serializedBytes()
}

final class AgentMailboxOperationsTests: XCTestCase {
    // MARK: - Routing

    func testMailboxesUseTheAgentOnlyWhenThereIsAnEngineAndAnAgent() {
        XCTAssertEqual(MailboxRouting.route(usesAgent: true, agentTransportAvailable: true,
                                            hasEngine: true), .agent)
        XCTAssertEqual(MailboxRouting.route(usesAgent: true, agentTransportAvailable: true,
                                            hasEngine: false), .ssh)
    }

    func testAnAgentlessDeploymentKeepsUsingTheWrapperOverSSH() {
        XCTAssertEqual(MailboxRouting.route(usesAgent: false, agentTransportAvailable: true,
                                            hasEngine: true), .ssh)
        XCTAssertEqual(MailboxRouting.route(usesAgent: false, agentTransportAvailable: false,
                                            hasEngine: true), .ssh)
        XCTAssertEqual(MailboxRouting.route(usesAgent: true, agentTransportAvailable: false,
                                            hasEngine: true), .ssh)
    }

    // MARK: - The wire

    func testListingRowsBecomeMailboxesWithTheirDetail() async throws {
        let payload = try listing([("admin@example.com", "( 6.0K / ~ ) [0%]"),
                                   ("fresh@example.com", "(  /  ) [%]")])
        let ops = AgentMailboxOperations(client: AgentClient(transport: MailMockTransport(
            onUnary: { path, _ in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Mail/ListMailboxes")
                return payload
            })), engineInstalled: true)

        let mailboxes = try await ops.list()
        XCTAssertEqual(mailboxes.map(\.address), ["admin@example.com", "fresh@example.com"])
        XCTAssertEqual(mailboxes[0].detail, "( 6.0K / ~ ) [0%]")
        XCTAssertEqual(mailboxes[1].detail, "(  /  ) [%]")
    }

    func testAnEmptyDetailBecomesNilNotAnEmptyString() async throws {
        let payload = try listing([("only@example.com", "")])
        let ops = AgentMailboxOperations(client: AgentClient(transport: MailMockTransport(
            onUnary: { _, _ in payload })), engineInstalled: true)
        let mailboxes = try await ops.list()
        XCTAssertNil(mailboxes.first?.detail)
    }

    func testAnEmptyListingIsNoMailboxesNotAFailure() async throws {
        let payload = try listing([])
        let ops = AgentMailboxOperations(client: AgentClient(transport: MailMockTransport(
            onUnary: { _, _ in payload })), engineInstalled: true)
        let mailboxes = try await ops.list()
        XCTAssertTrue(mailboxes.isEmpty)
    }

    func testThePasswordTravelsInTheRequestAndTheAddressIsSentVerbatim() async throws {
        let seen = LockedBox<(String, String, String)>()
        let payload = try listing([("new@example.com", "")])
        let ops = AgentMailboxOperations(client: AgentClient(transport: MailMockTransport(
            onUnary: { path, request in
                let sent = try Gryonixnexusd_V1_CreateMailboxRequest(serializedBytes: request)
                seen.value = (path, sent.address, sent.password)
                return payload
            })), engineInstalled: true)

        try await ops.add(address: "new@example.com", password: "s3cr3t-pass")
        XCTAssertEqual(seen.value?.0, "/gryonixnexusd.v1.Mail/CreateMailbox")
        XCTAssertEqual(seen.value?.1, "new@example.com")
        XCTAssertEqual(seen.value?.2, "s3cr3t-pass")
    }

    func testDeleteAndPasswordUseTheirOwnTypedRoutes() async throws {
        let paths = LockedBox<[String]>()
        paths.value = []
        let payload = try listing([])
        let ops = AgentMailboxOperations(client: AgentClient(transport: MailMockTransport(
            onUnary: { path, _ in
                paths.value = (paths.value ?? []) + [path]
                return payload
            })), engineInstalled: true)

        try await ops.delete(address: "old@example.com")
        try await ops.setPassword(address: "old@example.com", password: "pw")
        XCTAssertEqual(paths.value, ["/gryonixnexusd.v1.Mail/DeleteMailbox",
                                     "/gryonixnexusd.v1.Mail/SetMailboxPassword"])
    }

    // MARK: - Refusals

    func testABadAddressIsRefusedBeforeAnythingIsSent() async throws {
        let calls = LockedBox<Int>()
        calls.value = 0
        let ops = AgentMailboxOperations(client: AgentClient(transport: MailMockTransport(
            onUnary: { _, _ in
                calls.value = (calls.value ?? 0) + 1
                return Data()
            })), engineInstalled: true)

        for bad in ["", "-admin@example.com", "admin", "a@b@c", "admin@example.com; rm -rf /"] {
            do {
                try await ops.add(address: bad, password: "pw")
                XCTFail("\(bad) should have been refused")
            } catch {}
        }
        XCTAssertEqual(calls.value, 0, "not one of those reached the wire")
    }

    func testAnEmptyPasswordIsRefusedBeforeAnythingIsSent() async throws {
        let calls = LockedBox<Int>()
        calls.value = 0
        let ops = AgentMailboxOperations(client: AgentClient(transport: MailMockTransport(
            onUnary: { _, _ in
                calls.value = (calls.value ?? 0) + 1
                return Data()
            })), engineInstalled: true)
        do {
            try await ops.add(address: "a@b.com", password: "")
            XCTFail("an empty password should have been refused")
        } catch {}
        XCTAssertEqual(calls.value, 0)
    }

    func testWithoutTheEngineEveryCallRefusesAndNothingIsSent() async throws {
        let calls = LockedBox<Int>()
        calls.value = 0
        let ops = AgentMailboxOperations(client: AgentClient(transport: MailMockTransport(
            onUnary: { _, _ in
                calls.value = (calls.value ?? 0) + 1
                return Data()
            })), engineInstalled: false)
        do {
            _ = try await ops.list()
            XCTFail("a deployment without the engine has nothing to list")
        } catch {}
        XCTAssertEqual(calls.value, 0)
    }

    func testTheEnginesOwnWordsSurviveAsTheErrorMessage() async throws {
        let ops = AgentMailboxOperations(client: AgentClient(transport: MailMockTransport(
            onUnary: { _, _ in
                throw AgentError.rpc(code: "failed_precondition",
                                     message: "delmailuser: Mailbox data directory does not exist")
            })), engineInstalled: true)
        do {
            try await ops.delete(address: "gone@example.com")
            XCTFail("the failure should have been rethrown")
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(text.contains("Mailbox data directory does not exist"), text)
        }
    }
}
