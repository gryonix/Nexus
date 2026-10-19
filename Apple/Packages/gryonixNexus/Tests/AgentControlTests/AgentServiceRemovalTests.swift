import AgentClient
import Foundation
import ServerControl
import ServiceCatalog
import SwiftProtobuf
import XCTest
@testable import AgentControl

private struct MockTransport: AgentTransport {
    var onUnary: @Sendable (String, Data) async throws -> Data = { _, _ in Data() }
    var onStream: @Sendable (String, Data) -> AsyncThrowingStream<Data, Error> = { _, _ in
        AsyncThrowingStream { $0.finish() }
    }

    func unary(path: String, request: Data) async throws -> Data {
        try await onUnary(path, request)
    }

    func serverStream(path: String, request: Data) -> AsyncThrowingStream<Data, Error> {
        onStream(path, request)
    }
}

private func container(_ name: String, state: String) -> Gryonixnexusd_V1_Container {
    var container = Gryonixnexusd_V1_Container()
    container.name = name
    container.state = state
    return container
}

private func uninstallEvent(_ phase: Gryonixnexusd_V1_ServiceOperationPhase,
                            text: String = "",
                            installed: Bool? = nil,
                            containers: [Gryonixnexusd_V1_Container] = []) -> Data {
    var event = Gryonixnexusd_V1_UninstallEvent()
    event.phase = phase
    event.text = text
    if let installed {
        var status = Gryonixnexusd_V1_ServiceStatusResponse()
        status.installed = installed
        if !containers.isEmpty {
            var service = Gryonixnexusd_V1_Service()
            service.containers = containers
            status.service = service
        }
        event.status = status
    }
    return (try? event.serializedBytes()) ?? Data()
}

private func service(_ id: ServiceID) throws -> any ManagedService {
    try XCTUnwrap(ServiceRegistry.service(id))
}

final class AgentServiceRemovalTests: XCTestCase {
    // MARK: - Routing

    func testOnlyASingleServiceEverRoutesToTheAgent() {
        XCTAssertEqual(ServiceRemovalRouting.route(scope: .everything, usesAgent: true,
                                                   agentTransportAvailable: true), .ssh)
        XCTAssertEqual(ServiceRemovalRouting.route(scope: .service, usesAgent: true,
                                                   agentTransportAvailable: true), .agent)
        XCTAssertEqual(ServiceRemovalRouting.route(scope: .service, usesAgent: true,
                                                   agentTransportAvailable: false), .ssh)
        XCTAssertEqual(ServiceRemovalRouting.route(scope: .service, usesAgent: false,
                                                   agentTransportAvailable: true), .ssh)
    }

    // MARK: - Removal

    func testASuccessfulRemovalSendsPurgeFlagsAndReturnsTheStreamedLog() async throws {
        let sent = LockedBox<Gryonixnexusd_V1_RemoveServiceRequest>()
        let frames = [
            uninstallEvent(.started),
            uninstallEvent(.progress, text: "stopping containers"),
            uninstallEvent(.completed, installed: false)
        ]
        var chunks: [String] = []
        let removal = AgentServiceRemoval(client: AgentClient(transport: MockTransport(
            onStream: { path, request in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Uninstall/RemoveService")
                sent.value = try? Gryonixnexusd_V1_RemoveServiceRequest(serializedBytes: request)
                return AsyncThrowingStream { continuation in
                    for frame in frames { continuation.yield(frame) }
                    continuation.finish()
                }
            })))

        let log = try await removal.remove(try service(.nextcloud),
                                           purge: PurgeOptions(data: true, backups: false)) {
            chunks.append($0)
        }
        XCTAssertEqual(sent.value?.serviceID, "nextcloud")
        XCTAssertTrue(sent.value?.purgeData ?? false)
        XCTAssertFalse(sent.value?.purgeBackups ?? true)
        XCTAssertEqual(chunks, ["stopping containers\n"])
        XCTAssertTrue(log.contains("stopping containers"), log)
    }

    func testAFailedRemovalThrowsAndCarriesTheReReadStatus() async throws {
        let removal = AgentServiceRemoval(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(uninstallEvent(.progress, text: "stopping containers"))
                    continuation.yield(uninstallEvent(.completed, installed: true,
                                                      containers: [container("nextcloud-app", state: "running")]))
                    continuation.finish(throwing: AgentError.rpc(code: "internal",
                                                                 message: "could not remove the compose project"))
                }
            })))

        do {
            _ = try await removal.remove(try service(.nextcloud), purge: PurgeOptions(), onChunk: { _ in })
            XCTFail("a failed removal must throw")
        } catch let AgentControlError.operationFailed(underlying, status) {
            XCTAssertEqual(underlying, .rpc(code: "internal", message: "could not remove the compose project"))
            XCTAssertEqual(status.map(\.name), ["nextcloud-app"])
        }
    }

    func testARefusalBeforeAnythingRanKeepsItsOwnConnectCode() async throws {
        let refusal = AgentError.rpc(code: "not_found", message: "no such service")
        let removal = AgentServiceRemoval(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in AsyncThrowingStream { $0.finish(throwing: refusal) } })))

        do {
            _ = try await removal.remove(try service(.immich), purge: PurgeOptions(), onChunk: { _ in })
            XCTFail("a refused removal must throw")
        } catch let error as AgentError {
            XCTAssertEqual(error, refusal)
        }
    }
}
