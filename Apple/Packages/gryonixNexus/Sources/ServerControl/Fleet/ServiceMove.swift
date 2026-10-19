import Foundation
import ServiceCatalog

public enum ServiceMoveRefusal: Error, Equatable, Sendable {
    case notMovable(ServiceID)
    case noAgent
    case sameMachine
    case unknownMachine
    case targetDoesNotRunServices
    case noFront
}

public struct ServiceMoveRoute: Sendable, Equatable {
    public let service: ServiceID
    public let source: DeploymentNode
    public let target: DeploymentNode
    /// The machine whose Caddy answers the domain
    public let front: DeploymentNode

    public var sourceIsFront: Bool { source.id == front.id }
    public var targetIsFront: Bool { target.id == front.id }

    public var sourceEntryAddress: String? { sourceIsFront ? nil : source.endpoint.host }
    public var targetEntryAddress: String? { targetIsFront ? nil : target.endpoint.host }
}

/// Which services can travel between machines
public enum ServiceMovePolicy {
    static let tiedToTheirAddress: Set<ServiceID> = [
        .authelia, .adguardHome, .pihole, .headscale, .tailscaleNode, .vpnPanel
    ]

    public static func isMovable(_ service: any ManagedService, context: ServiceContext) -> Bool {
        let actions = service.actions(context)
        guard actions.restore != nil, actions.backup?.wrapper != nil else { return false }
        guard service.webIngress(context) != nil, service.firewallPorts(context).isEmpty else { return false }
        return !tiedToTheirAddress.contains(service.id) && !ServiceID.vpnProtocols.contains(service.id)
    }
}

public extension Deployment {
    var frontNode: DeploymentNode? {
        nodes.first { $0.servesOwnTraffic && $0.runsServices }
            ?? nodes.first { $0.terminatesPublicTraffic && $0.runsServices }
    }

    func moveRoute(of service: ServiceID, to target: UUID) -> Result<ServiceMoveRoute, ServiceMoveRefusal> {
        guard usesAgent else { return .failure(.noAgent) }
        guard let targetNode = nodes.first(where: { $0.id == target }) else { return .failure(.unknownMachine) }
        guard targetNode.runsServices else { return .failure(.targetDoesNotRunServices) }
        guard let source = node(running: service, placement: placement ?? ServicePlacement()) else {
            return .failure(.unknownMachine)
        }
        guard source.id != targetNode.id else { return .failure(.sameMachine) }
        guard let front = frontNode else { return .failure(.noFront) }
        return .success(ServiceMoveRoute(service: service, source: source, target: targetNode, front: front))
    }
}
