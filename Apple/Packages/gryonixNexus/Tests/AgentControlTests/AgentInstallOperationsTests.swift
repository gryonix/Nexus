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

private func installEvent(_ phase: Gryonixnexusd_V1_ServiceOperationPhase,
                          text: String = "",
                          containers: [Gryonixnexusd_V1_Container]? = nil) -> Data {
    var event = Gryonixnexusd_V1_InstallServiceEvent()
    event.phase = phase
    event.text = text
    if let containers {
        var service = Gryonixnexusd_V1_Service()
        service.containers = containers
        event.service = service
    }
    return (try? event.serializedBytes()) ?? Data()
}

final class AgentInstallOperationsTests: XCTestCase {
    // MARK: - Install

    func testASuccessfulInstallSendsTheWholeContextAndReturnsTheStreamedLog() async throws {
        let sent = LockedBox<Gryonixnexusd_V1_InstallServiceRequest>()
        let frames = [
            installEvent(.started),
            installEvent(.progress, text: "waiting for AdGuard Home to answer"),
            installEvent(.completed, containers: [container("adguardhome", state: "running")])
        ]
        var chunks: [String] = []
        let install = AgentInstallOperations(client: AgentClient(transport: MockTransport(
            onStream: { path, request in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Install/InstallService")
                sent.value = try? Gryonixnexusd_V1_InstallServiceRequest(serializedBytes: request)
                return AsyncThrowingStream { continuation in
                    for frame in frames { continuation.yield(frame) }
                    continuation.finish()
                }
            })))

        let context = AgentInstallContext(domain: "example.com", additionalDomains: ["example.net"],
                                          localOnly: false, adminUsername: "owner", language: .ru,
                                          settings: ["adguard_path": "/opt/adguardhome"])
        let log = try await install.install(.adguardHome, context: context) { chunks.append($0) }

        XCTAssertEqual(sent.value?.serviceID, "adguard-home")
        XCTAssertEqual(sent.value?.domain, "example.com")
        XCTAssertEqual(sent.value?.additionalDomains, ["example.net"])
        XCTAssertEqual(sent.value?.localOnly, false)
        XCTAssertEqual(sent.value?.adminUsername, "owner")
        XCTAssertEqual(sent.value?.language, "ru")
        XCTAssertEqual(sent.value?.settings, ["adguard_path": "/opt/adguardhome"])
        XCTAssertEqual(chunks, ["waiting for AdGuard Home to answer\n"])
        XCTAssertTrue(log.contains("waiting for AdGuard Home to answer"), log)
    }

    func testLocalOnlyAndDefaultsRoundTripFaithfully() async throws {
        let sent = LockedBox<Gryonixnexusd_V1_InstallServiceRequest>()
        let install = AgentInstallOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, request in
                sent.value = try? Gryonixnexusd_V1_InstallServiceRequest(serializedBytes: request)
                return AsyncThrowingStream { continuation in
                    continuation.yield(installEvent(.completed, containers: []))
                    continuation.finish()
                }
            })))

        let context = AgentInstallContext(domain: "srv.local", localOnly: true)
        _ = try await install.install(.adguardHome, context: context, onChunk: { _ in })

        XCTAssertEqual(sent.value?.localOnly, true)
        XCTAssertEqual(sent.value?.additionalDomains, [])
        XCTAssertEqual(sent.value?.adminUsername, "")
        XCTAssertEqual(sent.value?.language, "en")
        XCTAssertEqual(sent.value?.settings, [:])
    }

    // MARK: - The two-channel error rule

    func testAFailedInstallThrowsAndCarriesTheReReadStatus() async throws {
        let install = AgentInstallOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(installEvent(.progress, text: "pulling adguard/adguardhome"))
                    continuation.yield(installEvent(.completed,
                                                    containers: [container("adguardhome", state: "exited")]))
                    continuation.finish(throwing: AgentError.rpc(code: "internal",
                                                                 message: "docker pull failed: no space left on device"))
                }
            })))

        do {
            _ = try await install.install(.adguardHome, context: AgentInstallContext(domain: "example.com"),
                                          onChunk: { _ in })
            XCTFail("a failed install must throw")
        } catch let AgentControlError.operationFailed(underlying, status) {
            XCTAssertEqual(underlying, .rpc(code: "internal",
                                            message: "docker pull failed: no space left on device"))
            XCTAssertEqual(status.map(\.name), ["adguardhome"])
            XCTAssertEqual(status.map(\.status), ["Exited"])
        }
    }

    func testTheServersOwnWordsSurviveAsTheErrorMessage() async throws {
        let install = AgentInstallOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(installEvent(.completed, containers: []))
                    continuation.finish(throwing: AgentError.rpc(code: "internal",
                                                                 message: "caddy reload failed: syntax error"))
                }
            })))

        do {
            _ = try await install.install(.adguardHome, context: AgentInstallContext(domain: "example.com"),
                                          onChunk: { _ in })
            XCTFail("a failed install must throw")
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(text.contains("caddy reload failed: syntax error"), text)
        }
    }

    func testARefusalBeforeAnythingRanKeepsItsOwnConnectCode() async throws {
        let refusal = AgentError.rpc(code: "failed_precondition",
                                     message: "this agent build cannot install adguard-home yet")
        let install = AgentInstallOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in AsyncThrowingStream { $0.finish(throwing: refusal) } })))

        do {
            _ = try await install.install(.adguardHome, context: AgentInstallContext(domain: "example.com"),
                                          onChunk: { _ in })
            XCTFail("a refused install must throw")
        } catch let error as AgentError {
            XCTAssertEqual(error, refusal)
        }
    }

    func testAnUnsupportedServiceFallsBackWithoutEverReachingTheTransport() async throws {
        var reached = false
        var chunks: [String] = []
        let install = AgentInstallOperations(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in
                reached = true
                return AsyncThrowingStream { $0.finish() }
            })))

        do {
            _ = try await install.install(ServiceID(rawValue: "some-future-service"),
                                          context: AgentInstallContext(domain: "example.com")) {
                chunks.append($0)
            }
            XCTFail("an unmapped service must be refused before any call")
        } catch AgentControlError.unsupportedService {
            // Expected.
        }
        XCTAssertFalse(reached)
        XCTAssertTrue(chunks.isEmpty, "no progress event should ever be produced for a refused call")
    }
}
