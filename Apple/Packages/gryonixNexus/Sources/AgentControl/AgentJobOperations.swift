import AgentClient
import Foundation
import ServiceCatalog

public struct AgentJob: Sendable, Identifiable, Equatable {
    public let id: String
    public let kind: AgentJobKind
    public let subject: String
    public let started: Date
    public let finished: Date?
    public let outcome: AgentJobOutcome
    public let failure: String
    public let events: UInt64
    /// The install plan this run is part of
    public var partOf: String = ""
    /// Set on an install plan's own job
    public var planPurpose: AgentPlanPurpose = .add

    public var isRunning: Bool { outcome == .running }

    public init(id: String, kind: AgentJobKind, subject: String, started: Date,
                finished: Date?, outcome: AgentJobOutcome, failure: String, events: UInt64) {
        self.id = id
        self.kind = kind
        self.subject = subject
        self.started = started
        self.finished = finished
        self.outcome = outcome
        self.failure = failure
        self.events = events
    }
}

public enum AgentJobKind: String, Sendable, CaseIterable {
    case install, update, backup, restore, uninstall
    /// An install plan running every service again
    case repair, reinstall
    case serviceControl, containerUpdate, containerBackup, containerRemoval, containerControl
    /// Fetching a model onto the local engine
    case modelPull
    case securityControl
    /// `ApplyAgentUpdate`'s own journal
    case agentUpdate
    /// Sending or unpacking a service that moves between machines
    case move
    /// A kind this build has no name for
    case unknown
}

public enum AgentJobOutcome: String, Sendable {
    case running, succeeded, failed
    case cancelled
    case abandoned
    case unknown
}

/// Reading and re-attaching to the host's long runs
public struct AgentJobOperations: Sendable {
    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    /// What this host is doing, or has just done
    public func jobs(runningOnly: Bool = false) async throws -> [AgentJob] {
        let client = self.client
        let call = { @Sendable in try await client.listJobs(runningOnly: runningOnly) }
        let jobs = if let gate { try await gate.withSlot(call) } else { try await call() }
        return jobs.map(AgentJob.init(agent:))
    }

    /// Stop a run that is still going
    @discardableResult
    public func cancel(jobID: String) async throws -> AgentJob {
        let client = self.client
        let call = { @Sendable in try await client.cancelJob(jobID: jobID) }
        let job = if let gate { try await gate.withSlot(call) } else { try await call() }
        return AgentJob(agent: job)
    }

    public func watch(jobID: String, from sequence: UInt64 = 0,
                      onChunk: @escaping @Sendable (String) -> Void) async throws {
        for try await event in client.watchJob(jobID: jobID, fromSequence: sequence) {
            guard event.phase == .progress || event.phase == .started else { continue }
            guard !event.text.isEmpty else { continue }
            onChunk(event.text.hasSuffix("\n") ? event.text : event.text + "\n")
        }
    }
}

extension AgentJob {
    init(agent: Gryonixnexusd_V1_Job) {
        id = agent.jobID
        kind = AgentJobKind(agent: agent.kind)
        subject = agent.subject
        started = Date(timeIntervalSince1970: TimeInterval(agent.startedUnix))
        finished = agent.finishedUnix > 0
            ? Date(timeIntervalSince1970: TimeInterval(agent.finishedUnix))
            : nil
        outcome = AgentJobOutcome(agent: agent.outcome)
        failure = agent.failure
        events = agent.events
        partOf = agent.partOf
        planPurpose = AgentPlanPurpose(agent.planPurpose)
    }
}

extension AgentJobKind {
    init(agent: Gryonixnexusd_V1_JobKind) {
        switch agent {
        case .install: self = .install
        case .update: self = .update
        case .backup: self = .backup
        case .restore: self = .restore
        case .uninstall: self = .uninstall
        case .serviceControl: self = .serviceControl
        case .containerUpdate: self = .containerUpdate
        case .containerBackup: self = .containerBackup
        case .containerRemoval: self = .containerRemoval
        case .containerControl: self = .containerControl
        case .modelPull: self = .modelPull
        case .securityControl: self = .securityControl
        case .agentUpdate: self = .agentUpdate
        case .move: self = .move
        case .repair: self = .repair
        case .reinstall: self = .reinstall
        case .unspecified, .UNRECOGNIZED: self = .unknown
        }
    }
}

extension AgentJobOutcome {
    init(agent: Gryonixnexusd_V1_JobOutcome) {
        switch agent {
        case .running: self = .running
        case .succeeded: self = .succeeded
        case .failed: self = .failed
        case .abandoned: self = .abandoned
        case .cancelled: self = .cancelled
        case .unspecified, .UNRECOGNIZED: self = .unknown
        }
    }
}
