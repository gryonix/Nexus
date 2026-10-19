import AgentClient
import Foundation
import ServerControl
import SwiftProtobuf
import XCTest
@testable import AgentControl

private struct DKIMMockTransport: AgentTransport {
    var onUnary: @Sendable (String, Data) async throws -> Data = { _, _ in Data() }

    func unary(path: String, request: Data) async throws -> Data {
        try await onUnary(path, request)
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private func records(_ rows: [(String, String)]) throws -> Data {
    var list = Gryonixnexusd_V1_DkimRecordList()
    list.records = rows.map { name, value in
        var record = Gryonixnexusd_V1_DkimRecord()
        record.name = name
        record.value = value
        return record
    }
    return try list.serializedBytes()
}

final class AgentDkimOperationsTests: XCTestCase {
    // MARK: - Routing

    func testDKIMUsesTheAgentOnlyWhenThereIsAMailEngineAndAnAgent() {
        XCTAssertEqual(DKIMRouting.route(usesAgent: true, agentTransportAvailable: true,
                                         hasMailEngine: true), .agent)
        XCTAssertEqual(DKIMRouting.route(usesAgent: true, agentTransportAvailable: true,
                                         hasMailEngine: false), .ssh)
    }

    func testAnAgentlessDeploymentKeepsUsingTheSSHWrapper() {
        XCTAssertEqual(DKIMRouting.route(usesAgent: false, agentTransportAvailable: true,
                                         hasMailEngine: true), .ssh)
        XCTAssertEqual(DKIMRouting.route(usesAgent: false, agentTransportAvailable: false,
                                         hasMailEngine: true), .ssh)
        XCTAssertEqual(DKIMRouting.route(usesAgent: true, agentTransportAvailable: false,
                                         hasMailEngine: true), .ssh)
    }

    // MARK: - The wire

    func testRecordsComeBackWithNameAndValue() async throws {
        let payload = try records([("dkim._domainkey.example.com", "v=DKIM1; k=rsa; p=abc")])
        let ops = AgentDkimOperations(client: AgentClient(transport: DKIMMockTransport(
            onUnary: { path, _ in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Dkim/GetDkimRecords")
                return payload
            })))

        let result = try await ops.fetchRecords()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "dkim._domainkey.example.com")
        XCTAssertEqual(result[0].value, "v=DKIM1; k=rsa; p=abc")
        XCTAssertEqual(result[0].type, "TXT")
    }

    func testAnEngineWithNoKeyYetIsAnEmptyListNotAFailure() async throws {
        let payload = try records([])
        let ops = AgentDkimOperations(client: AgentClient(transport: DKIMMockTransport(
            onUnary: { _, _ in payload })))
        let result = try await ops.fetchRecords()
        XCTAssertTrue(result.isEmpty)
    }

    func testMultipleDomainsAllComeBackInOrder() async throws {
        let payload = try records([
            ("dkim._domainkey.a.example.com", "v=DKIM1; p=aaa"),
            ("dkim._domainkey.b.example.com", "v=DKIM1; p=bbb"),
        ])
        let ops = AgentDkimOperations(client: AgentClient(transport: DKIMMockTransport(
            onUnary: { _, _ in payload })))
        let result = try await ops.fetchRecords()
        XCTAssertEqual(result.map(\.name),
                       ["dkim._domainkey.a.example.com", "dkim._domainkey.b.example.com"])
    }

    // MARK: - Refusals

    func testTheEnginesOwnWordsSurviveAsTheErrorMessage() async throws {
        let ops = AgentDkimOperations(client: AgentClient(transport: DKIMMockTransport(
            onUnary: { _, _ in
                throw AgentError.rpc(code: "not_found",
                                     message: "no mail engine is installed on this host")
            })))
        do {
            _ = try await ops.fetchRecords()
            XCTFail("the failure should have been rethrown")
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(text.contains("no mail engine is installed on this host"), text)
        }
    }
}
