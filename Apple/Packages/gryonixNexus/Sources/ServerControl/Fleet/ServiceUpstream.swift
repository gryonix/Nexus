import Foundation
import ServiceCatalog

/// Where the ingress node sends a request for one service
public enum ServiceUpstream: Sendable, Hashable {
    case local

    /// The service runs on another node, reached across the mesh
    case mesh(nodeID: UUID, serverName: String)
}

/// Why a placement cannot be served
public enum PlacementProblem: Sendable, Hashable {
    case needsMeshToReachWorker(ServiceID)
}

public extension Deployment {
    var hasMesh: Bool {
        services.contains(.headscale) || services.contains(.tailscaleNode)
    }

    /// How the ingress reaches `service`
    func upstream(for service: ServiceID,
                  siteName: String,
                  placement: ServicePlacement = ServicePlacement()) -> ServiceUpstream? {
        guard let worker = node(running: service, placement: placement) else { return nil }
        if worker.terminatesPublicTraffic { return .local }
        if worker.servesOwnTraffic { return .local }
        return .mesh(nodeID: worker.id, serverName: siteName)
    }

    /// Placements this deployment cannot serve, with the reason
    func placementProblems(_ placement: ServicePlacement = ServicePlacement()) -> [PlacementProblem] {
        guard !hasMesh else { return [] }
        let workers = nodes.filter(\.runsServices)
        guard workers.count > 1 else { return [] }

        return services.compactMap { service in
            guard let worker = node(running: service, placement: placement),
                  !worker.terminatesPublicTraffic, !worker.servesOwnTraffic else { return nil }
            return .needsMeshToReachWorker(service)
        }
    }
}
