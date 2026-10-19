import Foundation
import ServiceCatalog

/// Which node runs which service
public struct ServicePlacement: Codable, Sendable, Hashable {
    /// `ServiceID.rawValue` → node id
    private var byService: [String: UUID]

    public init(_ byService: [String: UUID] = [:]) {
        self.byService = byService
    }

    public var isEmpty: Bool { byService.isEmpty }

    public subscript(service: ServiceID) -> UUID? {
        get { byService[service.rawValue] }
        set { byService[service.rawValue] = newValue }
    }

    public var entries: [String: UUID] { byService }
}

public extension Deployment {
    /// The node that runs `service`
    func node(running service: ServiceID, placement: ServicePlacement = ServicePlacement()) -> DeploymentNode? {
        if vpnRunsOnRelay, ServiceID.vpnFamily.contains(service) {
            return relayNode
        }
        let workers = nodes.filter(\.runsServices)
        if let named = placement[service],
           let match = workers.first(where: { $0.id == named }) {
            return match
        }
        return workers.first
    }

    func host(running service: ServiceID) -> SSHHostID {
        node(running: service, placement: placement ?? ServicePlacement())?.sshHost ?? servicesHost
    }

    var workerHosts: [SSHHostID] {
        let workers = nodes.filter(\.runsServices).map(\.sshHost)
        return workers.isEmpty ? [servicesHost] : workers
    }

    func servicesByNode(placement: ServicePlacement = ServicePlacement()) -> [UUID: Set<ServiceID>] {
        var grouped: [UUID: Set<ServiceID>] = [:]
        for service in services {
            guard let node = node(running: service, placement: placement) else { continue }
            grouped[node.id, default: []].insert(service)
        }
        return grouped
    }
}
