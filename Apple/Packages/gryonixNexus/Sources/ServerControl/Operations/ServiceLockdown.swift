import Foundation

public protocol AdminLockdownManaging: Sendable {
    func status() async throws -> AdminLockdownState

    func set(_ enabled: Bool) async throws -> AdminLockdownState

    /// Guards only the given vhosts
    func set(hosts: [String]) async throws -> AdminLockdownState
}

extension AdminLockdownManaging {
    /// Applies a state that status returned
    @discardableResult
    public func restore(_ state: AdminLockdownState) async throws -> AdminLockdownState {
        switch state {
        case .off: try await set(false)
        case .all: try await set(true)
        case .only(let hosts): try await set(hosts: hosts.sorted())
        }
    }
}

/// Which implementation a deployment's admin-guard toggle goes through
public enum LockdownRouting {
    public static func route(usesAgent: Bool, agentTransportAvailable: Bool) -> ServiceControlRoute {
        ServiceControlRouting.route(usesAgent: usesAgent, agentTransportAvailable: agentTransportAvailable)
    }
}

/// The SSH implementation: `StatusOperations`'s existing three lockdown methods, unchanged
public struct SSHAdminLockdown: AdminLockdownManaging {
    private let runner: any SSHCommandRunner
    private let config: DashboardConfig
    private let host: SSHHostID

    public init(runner: any SSHCommandRunner, config: DashboardConfig, host: SSHHostID) {
        self.runner = runner
        self.config = config
        self.host = host
    }

    public func status() async throws -> AdminLockdownState {
        try await StatusOperations(runner: runner, config: config).adminLockdownStatus(on: host)
    }

    public func set(_ enabled: Bool) async throws -> AdminLockdownState {
        try await StatusOperations(runner: runner, config: config).setAdminLockdown(enabled, on: host)
    }

    public func set(hosts: [String]) async throws -> AdminLockdownState {
        try await StatusOperations(runner: runner, config: config).setAdminLockdown(hosts: hosts, on: host)
    }
}
