import AgentClient
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

private func container(_ name: String, state: String, health: String = "") -> Gryonixnexusd_V1_Container {
    var container = Gryonixnexusd_V1_Container()
    container.name = name
    container.state = state
    container.health = health
    return container
}

private func event(_ phase: Gryonixnexusd_V1_ServiceOperationPhase,
                   text: String = "",
                   containers: [Gryonixnexusd_V1_Container] = []) -> Data {
    var event = Gryonixnexusd_V1_ServiceOperationEvent()
    event.phase = phase
    event.text = text
    if !containers.isEmpty {
        var service = Gryonixnexusd_V1_Service()
        service.containers = containers
        event.service = service
    }
    return (try? event.serializedBytes()) ?? Data()
}

private func service(_ id: ServiceID) throws -> any ManagedService {
    try XCTUnwrap(ServiceRegistry.service(id))
}

final class AgentCommandRunnerTests: XCTestCase {
    // MARK: - Routing

    func testRouteUsesAgentOnlyWhenItIsUsableFromThisDevice() {
        XCTAssertEqual(ServiceControlRouting.route(usesAgent: true, agentTransportAvailable: true), .agent)
        XCTAssertEqual(ServiceControlRouting.route(usesAgent: true, agentTransportAvailable: false), .ssh)
        XCTAssertEqual(ServiceControlRouting.route(usesAgent: false, agentTransportAvailable: true), .ssh)
        XCTAssertEqual(ServiceControlRouting.route(usesAgent: false, agentTransportAvailable: false), .ssh)
    }

    // MARK: - Addressing

    func testEveryVPNProtocolAddressesTheAggregateService() throws {
        for id in ServiceID.vpnProtocols.union([.vpnPanel]) {
            let service = try XCTUnwrap(ServiceRegistry.service(id), "\(id.rawValue) missing from the registry")
            XCTAssertEqual(AgentCommandRunner.agentID(for: service), "vpn",
                           "\(id.rawValue) must fold into the agent's aggregate vpn service")
        }
    }

    func testStatusSendsTheCatalogIdOnTheServiceStatusPath() async throws {
        var response = Gryonixnexusd_V1_ServiceStatusResponse()
        response.installed = true
        var reported = Gryonixnexusd_V1_Service()
        reported.containers = [container("vaultwarden", state: "running", health: "healthy")]
        response.service = reported
        let payload: Data = try response.serializedBytes()

        let runner = AgentCommandRunner(client: AgentClient(transport: MockTransport(
            onUnary: { path, request in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Control/ServiceStatus")
                let sent = try Gryonixnexusd_V1_ServiceStatusRequest(serializedBytes: request)
                XCTAssertEqual(sent.serviceID, "vaultwarden")
                return payload
            })))

        let statuses = try await runner.status(of: try service(.vaultwarden))
        XCTAssertEqual(statuses.map(\.name), ["vaultwarden"])
        XCTAssertEqual(statuses.first?.health, .ok)
    }

    func testNotInstalledIsAnEmptyListNotAThrow() async throws {
        var response = Gryonixnexusd_V1_ServiceStatusResponse()
        response.installed = false
        let payload: Data = try response.serializedBytes()

        let runner = AgentCommandRunner(client: AgentClient(transport: MockTransport(
            onUnary: { _, _ in payload })))

        let statuses = try await runner.status(of: try service(.immich))
        XCTAssertTrue(statuses.isEmpty)
    }

    // MARK: - Power

    func testRestartSendsTypedActionAndReturnsPostActionStatus() async throws {
        let frames = [
            event(.started),
            event(.progress, text: "Restarting 2/2"),
            event(.completed, containers: [
                container("mailcow-postfix", state: "running", health: "healthy"),
                container("mailcow-sogo", state: "exited")
            ])
        ]

        var progress: [String] = []
        let runner = AgentCommandRunner(client: AgentClient(transport: MockTransport(
            onStream: { path, request in
                XCTAssertEqual(path, "/gryonixnexusd.v1.Control/ControlService")
                let sent = try? Gryonixnexusd_V1_ControlServiceRequest(serializedBytes: request)
                XCTAssertEqual(sent?.serviceID, "mailcow")
                XCTAssertEqual(sent?.action, .restart)
                return AsyncThrowingStream { continuation in
                    for frame in frames { continuation.yield(frame) }
                    continuation.finish()
                }
            })))

        let statuses = try await runner.power(.restart, on: try service(.mailcow)) { line in
            progress.append(line)
        }

        XCTAssertEqual(progress, ["Restarting 2/2\n"])
        XCTAssertEqual(statuses.map(\.name), ["mailcow-postfix", "mailcow-sogo"])
        XCTAssertEqual(statuses.map(\.health), [.ok, .critical])
    }

    func testStopAndStartMapToTheirOwnWireActions() async throws {
        for (action, expected) in [(ServicePowerAction.stop, Gryonixnexusd_V1_ServiceAction.stop),
                                   (ServicePowerAction.start, .start)] {
            let runner = AgentCommandRunner(client: AgentClient(transport: MockTransport(
                onStream: { _, request in
                    let sent = try? Gryonixnexusd_V1_ControlServiceRequest(serializedBytes: request)
                    XCTAssertEqual(sent?.action, expected)
                    return AsyncThrowingStream { $0.finish() }
                })))
            _ = try await runner.power(action, on: try service(.nextcloud))
        }
    }

    func testAFailedRunThrowsAndCarriesTheFinalStatusWithIt() async throws {
        let frames = [
            event(.started),
            event(.completed, containers: [container("vpnpanel", state: "exited")])
        ]

        let runner = AgentCommandRunner(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in
                AsyncThrowingStream { continuation in
                    for frame in frames { continuation.yield(frame) }
                    continuation.finish(throwing: AgentError.rpc(code: "internal",
                                                                 message: "vpnpanel: docker exited 1"))
                }
            })))

        do {
            _ = try await runner.power(.restart, on: try service(.vpnPanel))
            XCTFail("a failed run must not report success")
        } catch let AgentControlError.operationFailed(underlying, status) {
            XCTAssertEqual(underlying, .rpc(code: "internal", message: "vpnpanel: docker exited 1"))
            XCTAssertEqual(status.map(\.name), ["vpnpanel"])
            XCTAssertEqual(status.map(\.health), [.critical])
            XCTAssertEqual((AgentControlError.operationFailed(underlying: underlying, status: status)
                            as LocalizedError).errorDescription, "vpnpanel: docker exited 1")
        }
    }

    func testARefusalBeforeTheActionKeepsItsOwnConnectCode() async throws {
        for code in ["invalid_argument", "not_found", "unavailable"] {
            let runner = AgentCommandRunner(client: AgentClient(transport: MockTransport(
                onStream: { _, _ in
                    AsyncThrowingStream { $0.finish(throwing: AgentError.rpc(code: code, message: "no")) }
                })))
            do {
                _ = try await runner.power(.restart, on: try service(.vaultwarden))
                XCTFail("a refused call must not report success")
            } catch let AgentError.rpc(thrown, _) {
                XCTAssertEqual(thrown, code)
            }
        }
    }

    func testAnUnknownPhaseFromANewerAgentIsIgnored() async throws {
        var unknown = Gryonixnexusd_V1_ServiceOperationEvent()
        unknown.phase = .UNRECOGNIZED(42)
        let frames = [(try? unknown.serializedBytes()) ?? Data(),
                      event(.completed, containers: [container("immich-server", state: "running")])]

        let runner = AgentCommandRunner(client: AgentClient(transport: MockTransport(
            onStream: { _, _ in
                AsyncThrowingStream { continuation in
                    for frame in frames { continuation.yield(frame) }
                    continuation.finish()
                }
            })))

        let statuses = try await runner.power(.restart, on: try service(.immich))
        XCTAssertEqual(statuses.map(\.name), ["immich-server"])
    }

    // MARK: - Container mapping

    func testContainerStateBecomesTheVocabularyTheDashboardReads() {
        XCTAssertEqual(ContainerStatus(agent: container("a", state: "running")).status, "Up")
        XCTAssertEqual(ContainerStatus(agent: container("a", state: "running", health: "healthy")).status,
                       "Up (healthy)")
        XCTAssertEqual(ContainerStatus(agent: container("a", state: "exited")).status, "Exited")
        XCTAssertEqual(ContainerStatus(agent: container("a", state: "exited")).health, .critical)
        XCTAssertEqual(ContainerStatus(agent: container("a", state: "restarting")).status, "Restarting")
        XCTAssertEqual(ContainerStatus(agent: container("a", state: "restarting")).health, .warning)
        XCTAssertEqual(ContainerStatus(agent: container("a", state: "")).status, "Unknown")
    }
}
