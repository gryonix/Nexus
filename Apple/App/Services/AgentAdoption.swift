import Foundation
import ServerControl
import ServerControlSSH
import ServiceCatalog
import AgentClient
import AgentClientSSH

@available(macOS 15.0, *)
enum AgentAdoption {
    struct Result: Sendable {
        let device: Gryonixnexusd_V1_Device
        /// What the machine calls itself
        let hostname: String
        let domains: [String]
        let discoveredServices: [Gryonixnexusd_V1_Service]
        let serviceIDs: Set<ServiceID>
        let installedOutside: Set<String>
        /// Human-readable notes about anything ambiguous the scan hit
        let notes: [String]
    }

    enum Stage: Sendable, Equatable {
        case connecting
        case pairing
        case discovering
    }

    enum Failure: Error, LocalizedError {
        /// SSH itself did not get through
        case unreachable(String)
        case keyRefused(String)
        /// Connected, and nothing answered as `gryonixnexusd`
        case noAgent(String)
        case agentFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreachable(let detail), .keyRefused(let detail),
                 .noAgent(let detail), .agentFailed(let detail):
                return detail
            }
        }

        static func fromConnection(_ error: Error) -> Failure {
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let text = detail + " " + String(describing: error)
            if text.localizedCaseInsensitiveContains("authentication")
                || text.localizedCaseInsensitiveContains("allAuthenticationOptionsFailed") {
                return .keyRefused(detail)
            }
            return .unreachable(detail)
        }
    }

    static let pairCodeCommand = "sudo /usr/local/bin/gryonixnexusd pair-code"

    static func adopt(deployment: Deployment,
                      deviceLabel: String,
                      onStage: @Sendable (Stage) async -> Void) async throws -> Result {
        await onStage(.connecting)
        let session: AgentConnection.Session
        do {
            session = try await AgentConnection.open(deployment: deployment)
        } catch {
            throw Failure.fromConnection(error)
        }
        do {
            let result = try await run(session: session, deployment: deployment,
                                       deviceLabel: deviceLabel, onStage: onStage)
            await session.runner.disconnect()
            return result
        } catch {
            await session.runner.disconnect()
            throw error
        }
    }

    private static func run(session: AgentConnection.Session,
                            deployment: Deployment,
                            deviceLabel: String,
                            onStage: @Sendable (Stage) async -> Void) async throws -> Result {
        let state: Gryonixnexusd_V1_State
        do {
            state = try await session.client.getState()
        } catch {
            throw Failure.noAgent((error as? LocalizedError)?.errorDescription
                                  ?? error.localizedDescription)
        }

        await onStage(.pairing)
        let device = try await AgentDeviceEnrolment.enrol(session: session,
                                                          deployment: deployment,
                                                          label: deviceLabel)

        await onStage(.discovering)
        let discovered = try await session.client.discover()
        let ids = AgentServiceMapping.serviceIDs(
            forAgentServices: discovered.services.map { ($0.id, $0.containers.map(\.name)) })
        let strangers = Set(state.services.filter(\.installedOutside).map(\.id))
        return Result(device: device,
                      hostname: state.host.hostname,
                      domains: state.host.domains,
                      discoveredServices: discovered.services,
                      serviceIDs: ids,
                      installedOutside: strangers,
                      notes: discovered.notes)
    }
}

enum AgentAdoptionError: LocalizedError {
    case pairCodeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .pairCodeUnavailable(let detail):
            if detail.isEmpty {
                return UIL10n.string("The agent could not issue a pairing code.")
            }
            return UIL10n.string("The agent could not issue a pairing code: %@", detail)
        }
    }
}
