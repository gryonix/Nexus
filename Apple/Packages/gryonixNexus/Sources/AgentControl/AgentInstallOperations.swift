import AgentClient
import Foundation
import ServerControl
import ServiceCatalog

public struct AgentInstallOperations: Sendable {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    @discardableResult
    public func provisionHost(_ context: AgentInstallContext) async throws
        -> (written: [String], controlUser: String, notes: [String]) {
        let client = self.client
        let call = { @Sendable in
            try await client.provisionHost(domain: context.domain,
                                           additionalDomains: context.additionalDomains,
                                           localOnly: context.localOnly,
                                           adminUsername: context.adminUsername,
                                           language: context.language.rawValue,
                                           settings: context.settings,
                                           host: context.host)
        }
        let response = if let gate { try await gate.withSlot(call) } else { try await call() }
        return (response.written, response.controlUser, response.notes)
    }

    /// Start an install and narrate it
    @discardableResult
    public func install(_ service: ServiceID, context: AgentInstallContext,
                        onJobID: (@Sendable (String) -> Void)? = nil,
                        onChunk: @escaping @Sendable (String) -> Void,
                        onWarning: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let id = try agentID(service)
        let client = self.client
        var log = ""
        var status: [ContainerStatus]?
        var announcedJob = false
        do {
            for try await event in client.installService(serviceID: id,
                                                          domain: context.domain,
                                                          additionalDomains: context.additionalDomains,
                                                          localOnly: context.localOnly,
                                                          adminUsername: context.adminUsername,
                                                          language: context.language.rawValue,
                                                          settings: context.settings,
                                                          host: context.host) {
                if !announcedJob, !event.jobID.isEmpty {
                    announcedJob = true
                    onJobID?(event.jobID)
                }
                switch event.phase {
                case .progress:
                    let line = event.text.hasSuffix("\n") ? event.text : event.text + "\n"
                    log += line
                    onChunk(line)
                    if event.stream == "warning" {
                        onWarning?(event.text)
                    }
                case .completed:
                    status = event.service.containers.map(ContainerStatus.init(agent:))
                case .started, .unspecified, .UNRECOGNIZED:
                    break
                }
            }
        } catch {
            guard let status else { throw error }
            throw AgentControlError.operationFailed(underlying: Self.asAgentError(error), status: status)
        }
        return OutputTail.tail(log)
    }

    @discardableResult
    public func watch(jobID: String, from sequence: UInt64 = 0,
                      onChunk: @escaping @Sendable (String) -> Void,
                      onWarning: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let client = self.client
        var log = ""
        var status: [ContainerStatus]?
        do {
            for try await event in client.watchInstall(jobID: jobID, fromSequence: sequence) {
                switch event.phase {
                case .progress:
                    let line = event.text.hasSuffix("\n") ? event.text : event.text + "\n"
                    log += line
                    onChunk(line)
                    if event.stream == "warning" {
                        onWarning?(event.text)
                    }
                case .completed:
                    status = event.service.containers.map(ContainerStatus.init(agent:))
                case .started, .unspecified, .UNRECOGNIZED:
                    break
                }
            }
        } catch {
            guard let status else { throw error }
            throw AgentControlError.operationFailed(underlying: Self.asAgentError(error), status: status)
        }
        return OutputTail.tail(log)
    }

    /// The agent installs the whole list itself
    public func startPlan(_ services: [(ServiceID, AgentInstallContext)],
                          purpose: AgentPlanPurpose = .add) async throws -> AgentInstallPlan {
        let requests = try services.map { service, context in
            AgentClient.installRequest(serviceID: try agentID(service), domain: context.domain,
                                       additionalDomains: context.additionalDomains,
                                       localOnly: context.localOnly, adminUsername: context.adminUsername,
                                       language: context.language.rawValue, settings: context.settings,
                                       host: context.host)
        }
        let client = self.client
        let call = { @Sendable in try await client.startInstallPlan(requests, purpose: purpose.wire) }
        let plan = if let gate { try await gate.withSlot(call) } else { try await call() }
        return AgentInstallPlan(plan)
    }

    /// A plan by id; empty id means newest
    public func plan(_ id: String = "") async throws -> AgentInstallPlan {
        AgentInstallPlan(try await client.installPlan(id: id))
    }

    /// Follows a plan's own log until the plan ends
    public func watchPlan(_ id: String, from sequence: UInt64,
                          onLine: @escaping @Sendable (_ next: UInt64, _ stream: String, _ text: String) -> Void) async throws {
        for try await event in client.watchJob(jobID: id, fromSequence: sequence) {
            guard event.phase == .progress || event.phase == .started else { continue }
            onLine(event.sequence + 1, event.stream, event.text)
        }
    }

    private func agentID(_ service: ServiceID) throws -> String {
        guard let id = AgentServiceMapping.agentID(for: service) else {
            throw AgentControlError.unsupportedService(service.rawValue)
        }
        return id
    }

    private static func asAgentError(_ error: Error) -> AgentError {
        error as? AgentError ?? .transport("\(error)")
    }
}

public struct AgentInstallContext: Sendable {
    public var domain: String
    public var additionalDomains: [String]
    /// Whether Caddy signs its own certificate instead of asking ACME
    public var localOnly: Bool
    public var adminUsername: String
    public var language: AppLanguage

    public var settings: [String: String]

    public var host: AgentHostSurface

    public init(domain: String, additionalDomains: [String] = [], localOnly: Bool = false,
               adminUsername: String = "", language: AppLanguage = .en,
               settings: [String: String] = [:],
               host: AgentHostSurface = AgentHostSurface()) {
        self.domain = domain
        self.additionalDomains = additionalDomains
        self.localOnly = localOnly
        self.adminUsername = adminUsername
        self.language = language
        self.settings = settings
        self.host = host
    }
}

/// Services an agent installs one by one on its own
public struct AgentInstallPlan: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case pending, running, done, failed, skipped
    }

    public struct Item: Sendable, Equatable {
        public let agentServiceID: String
        public let state: State
        public let jobID: String
        public let failure: String

        public init(agentServiceID: String, state: State, jobID: String = "", failure: String = "") {
            self.agentServiceID = agentServiceID
            self.state = state
            self.jobID = jobID
            self.failure = failure
        }
    }

    public let id: String
    public let items: [Item]
    public let finished: Bool
    public let cancelled: Bool
    public var purpose: AgentPlanPurpose = .add

    public init(id: String, items: [Item], finished: Bool, cancelled: Bool = false) {
        self.id = id
        self.items = items
        self.finished = finished
        self.cancelled = cancelled
    }

    init(_ wire: Gryonixnexusd_V1_InstallPlan) {
        self.init(id: wire.planID,
                  items: wire.items.map { Item(agentServiceID: $0.serviceID, state: State($0.state),
                                               jobID: $0.jobID, failure: $0.failure) },
                  finished: wire.finished, cancelled: wire.cancelled)
        purpose = AgentPlanPurpose(wire.purpose)
    }

    /// Whether a plan exists and still has work left
    public var isRunning: Bool { !id.isEmpty && !finished }

    /// Items with an outcome
    public var settled: Int { items.filter { [.done, .failed, .skipped].contains($0.state) }.count }

    public var failures: [Item] { items.filter { $0.state == .failed } }
}

/// Why an install plan runs
public enum AgentPlanPurpose: String, Sendable, Codable {
    case add, setup, repair, reinstall

    init(_ wire: Gryonixnexusd_V1_InstallPlanPurpose) {
        switch wire {
        case .setup: self = .setup
        case .repair: self = .repair
        case .reinstall: self = .reinstall
        default: self = .add
        }
    }

    var wire: Gryonixnexusd_V1_InstallPlanPurpose {
        switch self {
        case .add: .add
        case .setup: .setup
        case .repair: .repair
        case .reinstall: .reinstall
        }
    }
}

extension AgentInstallPlan.State {
    init(_ wire: Gryonixnexusd_V1_InstallPlanItemState) {
        switch wire {
        case .running: self = .running
        case .done: self = .done
        case .failed: self = .failed
        case .skipped: self = .skipped
        default: self = .pending
        }
    }
}
