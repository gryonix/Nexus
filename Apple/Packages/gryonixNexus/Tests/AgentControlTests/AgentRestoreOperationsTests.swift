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

private func restoreEvent(_ phase: Gryonixnexusd_V1_ServiceOperationPhase,
                          text: String = "",
                          installed: Bool? = nil,
                          containers: [Gryonixnexusd_V1_Container] = []) -> Data {
    var event = Gryonixnexusd_V1_RestoreEvent()
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

private struct UnknownFutureService: ManagedService {
    let id = ServiceID(rawValue: "some-future-service")
    let displayName = "Future Service"
    let systemImage = "questionmark.circle"
    let category = ServiceCategory.files
    let runtime = ServiceRuntime.docker(composeProject: "future-service")

    func composeFile(_ context: ServiceContext) -> ComposeFile? { nil }
    func setupSteps(_ context: ServiceContext) -> [String] { [] }
    func firewallPorts(_ context: ServiceContext) -> [FirewallPort] { [] }
    func webIngress(_ context: ServiceContext) -> WebIngress? { nil }
    func dnsHostnames(_ context: ServiceContext) -> [String] { [] }

    func actions(_ context: ServiceContext) -> ServiceActions {
        ServiceActions(statusProbe: .composeProject(
            project: "future-service",
            list: PrivilegedCommand(binaryPath: "/usr/bin/docker",
                                    arguments: "compose -p future-service ps")))
    }

    func updateSpec(_ context: ServiceContext) -> UpdateSpec {
        UpdateSpec(images: ["example/future-service:1"])
    }
}

final class AgentRestoreOperationsTests: XCTestCase {
    // MARK: - Routing

    func testRestoreRoutingHasNoPerServiceExceptionUnlikeBackupRouting() {
        XCTAssertEqual(RestoreRouting.route(usesAgent: true, agentTransportAvailable: true), .agent)
        XCTAssertEqual(RestoreRouting.route(usesAgent: true, agentTransportAvailable: false), .ssh)
        XCTAssertEqual(RestoreRouting.route(usesAgent: false, agentTransportAvailable: true), .ssh)
    }

    // MARK: - Restore

    func testASuccessfulRestoreSendsTheArchivePathAndPassphraseAndReturnsTheStreamedLog() async throws {
        let sent = LockedBox<Gryonixnexusd_V1_RunRestoreRequest>()
        let frames = [
            restoreEvent(.started),
            restoreEvent(.progress, text: "restoring nextcloud data"),
            restoreEvent(.completed, installed: true,
                        containers: [container("nextcloud-app", state: "running")])
        ]
        var chunks: [String] = []
        let restore = AgentRestoreOperations(client: AgentClient(transport: MockTransport(
            onStream: { path, request in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Restore/RunRestore")
                sent.value = try? Gryonixnexusd_V1_RunRestoreRequest(serializedBytes: request)
                return AsyncThrowingStream { continuation in
                    for frame in frames { continuation.yield(frame) }
                    continuation.finish()
                }
            })))

        let log = try await restore.restore(try service(.nextcloud),
                                            archivePath: "/opt/backups/nextcloud/2026.tar.gz",
                                            passphrase: "hunter2") {
            chunks.append($0)
        }
        XCTAssertEqual(sent.value?.serviceID, "nextcloud")
        XCTAssertEqual(sent.value?.archivePath, "/opt/backups/nextcloud/2026.tar.gz")
        XCTAssertEqual(sent.value?.passphrase, "hunter2")
        XCTAssertEqual(chunks, ["restoring nextcloud data\n"])
        XCTAssertTrue(log.contains("restoring nextcloud data"), log)
    }

    func testANilPassphraseIsSentAsEmptyNeverOmitted() async throws {
        let sent = LockedBox<Gryonixnexusd_V1_RunRestoreRequest>()
        let restore = AgentRestoreOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, request in
                sent.value = try? Gryonixnexusd_V1_RunRestoreRequest(serializedBytes: request)
                return AsyncThrowingStream { continuation in
                    continuation.yield(restoreEvent(.completed, installed: true))
                    continuation.finish()
                }
            })))

        _ = try await restore.restore(try service(.nextcloud),
                                      archivePath: "/opt/backups/nextcloud/plain.tar.gz",
                                      passphrase: nil, onChunk: { _ in })
        XCTAssertEqual(sent.value?.passphrase, "")
    }

    func testAFailedRestoreThrowsAndCarriesTheReReadStatus() async throws {
        let restore = AgentRestoreOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(restoreEvent(.progress, text: "restoring nextcloud data"))
                    continuation.yield(restoreEvent(.completed, installed: true,
                                                    containers: [container("nextcloud-app", state: "exited")]))
                    continuation.finish(throwing: AgentError.rpc(code: "internal",
                                                                 message: "the nextcloud database could not be restored"))
                }
            })))

        do {
            _ = try await restore.restore(try service(.nextcloud), archivePath: "/opt/backups/nextcloud/x.tar.gz",
                                          passphrase: nil, onChunk: { _ in })
            XCTFail("a failed restore must throw")
        } catch let AgentControlError.operationFailed(underlying, status) {
            XCTAssertEqual(underlying, .rpc(code: "internal", message: "the nextcloud database could not be restored"))
            XCTAssertEqual(status.map(\.name), ["nextcloud-app"])
        }
    }

    func testARefusalBeforeAnythingRanKeepsItsOwnConnectCode() async throws {
        let refusal = AgentError.rpc(code: "failed_precondition",
                                     message: "this server has no restore wrapper")
        let restore = AgentRestoreOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in AsyncThrowingStream { $0.finish(throwing: refusal) } })))

        do {
            _ = try await restore.restore(try service(.immich), archivePath: "/opt/backups/immich/x.tar.gz",
                                          passphrase: nil, onChunk: { _ in })
            XCTFail("a refused restore must throw")
        } catch let error as AgentError {
            XCTAssertEqual(error, refusal)
        }
    }

    func testAnUnsupportedServiceFallsBackWithoutEverReachingTheTransport() async throws {
        var reached = false
        let restore = AgentRestoreOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in
                reached = true
                return AsyncThrowingStream { $0.finish() }
            })))

        do {
            _ = try await restore.restore(UnknownFutureService(),
                                          archivePath: "/opt/backups/future-service/x.tar.gz",
                                          passphrase: nil, onChunk: { _ in })
            XCTFail("an unmapped service must be refused before any call")
        } catch AgentControlError.unsupportedService {
            // Expected.
        }
        XCTAssertFalse(reached)
    }
}
