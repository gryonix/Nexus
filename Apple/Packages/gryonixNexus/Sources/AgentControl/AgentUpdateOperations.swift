import AgentClient
import Foundation
import ServerControl
import ServiceCatalog

public struct AgentUpdateOperations: ServiceUpdateManaging {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    /// What has moved, across the whole server
    public func check() async throws -> [ServiceUpdateReport] {
        let result = try await mapping { try await client.checkUpdates() }
        return result.services.map { status in
            ServiceUpdateReport(service: Self.serviceID(forAgentID: status.serviceID),
                                status: Self.status(from: status))
        }
    }

    /// Applies one service's update, streaming the wrapper's output
    @discardableResult
    public func run(_ service: ServiceID,
                    onChunk: @escaping @Sendable (String) -> Void = { _ in }) async throws -> ServiceUpdateRunRecord {
        let id = try agentID(service)
        let client = self.client
        var record: ServiceUpdateRunRecord?
        do {
            for try await event in client.runUpdate(serviceID: id) {
                switch event.phase {
                case .progress:
                    let line = event.text.hasSuffix("\n") ? event.text : event.text + "\n"
                    onChunk(line)
                case .completed:
                    record = ServiceUpdateRunRecord(service: service,
                                                    outcome: Self.outcome(event.outcome, reason: event.reason))
                case .started, .unspecified, .UNRECOGNIZED:
                    break
                }
            }
        } catch {
            guard let record else {
                if case let AgentError.rpc(_, message) = error, !message.isEmpty {
                    throw ServerControlError.commandFailed(command: "update", exitCode: nil,
                                                           stderr: message)
                }
                throw error
            }
            return record
        }
        guard let record else {
            throw ServerControlError.commandFailed(command: "update", exitCode: nil,
                                                   stderr: "the agent sent no result for this update")
        }
        return record
    }

    /// The stored schedule
    public func loadSchedule() async throws -> AutoUpdateSettings {
        let policy = try await mapping { try await client.getUpdatePolicy() }
        return AutoUpdateSettings(schedule: CommandCatalog.Backups.Schedule(wrapperArgument: policy.schedule),
                                  services: Set(policy.services))
    }

    /// What the last scheduled (or manual) run left behind
    public func loadStatus() async throws -> ServiceUpdateRunLog {
        let policy = try await mapping { try await client.getUpdatePolicy() }
        let lastRun = policy.lastRunAt > 0
            ? Date(timeIntervalSince1970: Double(policy.lastRunAt) / 1000)
            : nil
        let records = policy.lastRun.map { record in
            ServiceUpdateRunRecord(service: Self.serviceID(forAgentID: record.serviceID),
                                   outcome: Self.outcome(record.outcome, reason: record.reason))
        }
        return ServiceUpdateRunLog(lastRun: lastRun, records: records)
    }

    /// Writes a new schedule
    public func save(_ settings: AutoUpdateSettings) async throws {
        _ = try await mapping {
            try await client.setUpdateSchedule(schedule: settings.schedule.wrapperArgument,
                                               services: settings.services.sorted())
        }
    }

    // MARK: - Helpers

    private func agentID(_ service: ServiceID) throws -> String {
        guard let id = AgentServiceMapping.agentID(for: service) else {
            throw AgentControlError.unsupportedService(service.rawValue)
        }
        return id
    }

    /// The app's id for one of the agent's own ids
    private static func serviceID(forAgentID id: String) -> ServiceID {
        AgentServiceMapping.serviceIDs(forAgentIDs: [id]).first ?? ServiceID(rawValue: id)
    }

    private static func status(from status: Gryonixnexusd_V1_ServiceUpdateStatus) -> ServiceUpdateStatus {
        switch status.availability {
        case .current: return .current
        case .available: return .available(images: status.movedImages)
        case .unknown, .unspecified, .UNRECOGNIZED: return .unknown
        }
    }

    private static func outcome(_ outcome: Gryonixnexusd_V1_UpdateOutcome,
                                reason: String) -> ServiceUpdateRunRecord.Outcome {
        switch outcome {
        case .updated: return .updated
        case .rolledBack: return .rolledBack(reason: reason)
        case .failed, .unspecified, .UNRECOGNIZED: return .failed(reason: reason)
        }
    }

    private func mapping<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        do {
            guard let gate else { return try await body() }
            return try await gate.withSlot(body)
        } catch let error as AgentError {
            guard case .rpc(_, let message) = error, !message.isEmpty else { throw error }
            throw ServerControlError.commandFailed(command: "update", exitCode: nil, stderr: message)
        }
    }
}
