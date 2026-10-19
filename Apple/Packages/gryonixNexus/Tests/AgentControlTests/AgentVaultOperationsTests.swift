import AgentClient
import Foundation
import ServerControl
import SwiftProtobuf
import XCTest
@testable import AgentControl

private struct VaultMockTransport: AgentTransport {
    var onUnary: @Sendable (String, Data) async throws -> Data = { _, _ in Data() }

    func unary(path: String, request: Data) async throws -> Data {
        try await onUnary(path, request)
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private func entry(id: String, password: String, at: Int64, by: String) -> Gryonixnexusd_V1_VaultEntry {
    var entry = Gryonixnexusd_V1_VaultEntry()
    entry.id = id
    entry.host = "single"
    entry.title = "Vaultwarden"
    entry.password = password
    entry.updatedAt = at
    entry.updatedBy = by
    return entry
}

@available(macOS 15.0, *)
final class AgentVaultOperationsTests: XCTestCase {
    /// Captures the request the operations layer actually sent
    private func sent(_ entries: [Gryonixnexusd_V1_VaultEntry],
                      deviceUID: String = "phone-a") async throws
        -> [Gryonixnexusd_V1_VaultEntry] {
        let box = Box()
        let transport = VaultMockTransport { path, request in
            XCTAssertEqual(path, "/gryonixnexusd.v1.Vault/PutVaultEntries")
            let decoded = try Gryonixnexusd_V1_PutVaultEntriesRequest(serializedBytes: request)
            await box.set(decoded.entries)
            return try Gryonixnexusd_V1_VaultSnapshot().serializedBytes()
        }
        let operations = AgentVaultOperations(client: AgentClient(transport: transport),
                                              deviceUID: deviceUID)
        _ = try await operations.save(entries)
        return await box.value
    }

    private actor Box {
        var value: [Gryonixnexusd_V1_VaultEntry] = []
        func set(_ entries: [Gryonixnexusd_V1_VaultEntry]) { value = entries }
    }

    func testAZeroTimestampIsSentAsZero() async throws {
        let out = try await sent([entry(id: "single|Vaultwarden", password: "from-the-report",
                                        at: 0, by: "agent")])
        XCTAssertEqual(out.first?.updatedAt, 0)
    }

    func testAnEditKeepsTheCallersTime() async throws {
        let out = try await sent([entry(id: "single|Vaultwarden", password: "typed",
                                        at: 1_700_000_000, by: "phone-a")])
        XCTAssertEqual(out.first?.updatedAt, 1_700_000_000)
    }

    func testAnEmptyWriterIsFilledInWithThisDevice() async throws {
        let out = try await sent([entry(id: "single|Vaultwarden", password: "typed",
                                        at: 1_700_000_000, by: "")])
        XCTAssertEqual(out.first?.updatedBy, "phone-a")
    }

    func testANamedWriterIsLeftAlone() async throws {
        let out = try await sent([entry(id: "single|Vaultwarden", password: "from-the-report",
                                        at: 0, by: "agent")])
        XCTAssertEqual(out.first?.updatedBy, "agent")
    }

    func testDeletedEntriesAreNotOfferedAsEntries() async throws {
        var snapshot = Gryonixnexusd_V1_VaultSnapshot()
        var gone = entry(id: "gone", password: "", at: 100, by: "phone-b")
        gone.deleted = true
        snapshot.entries = [entry(id: "kept", password: "hunter2", at: 100, by: "phone-b"), gone]
        let payload: Data = try snapshot.serializedBytes()
        let transport = VaultMockTransport { _, _ in payload }
        let operations = AgentVaultOperations(client: AgentClient(transport: transport))
        let entries: [Gryonixnexusd_V1_VaultEntry] = try await operations.entries()
        XCTAssertEqual(entries.map { $0.id }, ["kept"])
    }
}
