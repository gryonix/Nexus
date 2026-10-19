import Foundation
import ServiceCatalog

public enum NodeCapability: String, Codable, Sendable, Hashable, CaseIterable {
    case ingress
    /// Runs services
    case worker
}

/// One machine in a deployment
public struct DeploymentNode: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    /// User-facing label
    public var name: String
    /// How the app reaches it over SSH
    public var endpoint: HostEndpoint
    public var capabilities: Set<NodeCapability>
    /// Which ingress node publishes this worker's services
    public var routedThrough: UUID?
    public var servesOwnTraffic: Bool
    public var legacySlot: LegacySlot?
    /// The distribution answer for THIS host
    public var distribution: String?

    public enum LegacySlot: String, Codable, Sendable, Hashable {
        case vps
        case home
    }

    public init(
        id: UUID,
        name: String = "",
        endpoint: HostEndpoint,
        capabilities: Set<NodeCapability>,
        routedThrough: UUID? = nil,
        servesOwnTraffic: Bool = false,
        legacySlot: LegacySlot? = nil,
        distribution: String? = nil
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.capabilities = capabilities
        self.routedThrough = routedThrough
        self.servesOwnTraffic = servesOwnTraffic
        self.legacySlot = legacySlot
        self.distribution = distribution
    }

    public var terminatesPublicTraffic: Bool { capabilities.contains(.ingress) }
    public var runsServices: Bool { capabilities.contains(.worker) }

    /// How the transport addresses this machine
    public var sshHost: SSHHostID {
        if let legacySlot { return SSHHostID(kind: .slot(legacySlot)) }
        return .node(id)
    }
}

public extension Deployment {
    /// The deployment as a list of nodes
    var nodes: [DeploymentNode] {
        if let stored = storedNodes, !stored.isEmpty { return stored }
        return derivedNodes
    }

    /// The two-host shape, as nodes
    var derivedNodes: [DeploymentNode] {
        switch topology {
        case .singleHost:
            return [
                DeploymentNode(
                    id: Self.nodeID(for: id, slot: .vps),
                    endpoint: entry,
                    capabilities: [.ingress, .worker],
                    legacySlot: .vps
                )
            ]
        case .vpsRelayWithHomeBackend:
            let relayID = Self.nodeID(for: id, slot: .vps)
            return [
                DeploymentNode(
                    id: relayID,
                    endpoint: entry,
                    capabilities: [.ingress],
                    legacySlot: .vps
                ),
                DeploymentNode(
                    id: Self.nodeID(for: id, slot: .home),
                    endpoint: HostEndpoint(host: homeWGAddress ?? "",
                                           port: entry.port,
                                           user: entry.user),
                    capabilities: [.worker],
                    routedThrough: relayID,
                    servesOwnTraffic: true,
                    legacySlot: .home
                )
            ]
        }
    }

    /// The node that runs services — where an install goes
    var servicesNode: DeploymentNode? { nodes.first(where: \.runsServices) }

    /// The node that answers on the public address
    var ingressNode: DeploymentNode? { nodes.first(where: \.terminatesPublicTraffic) }

    var teardownOrder: [DeploymentNode] {
        var remaining = nodes
        var ordered: [DeploymentNode] = []
        while !remaining.isEmpty {
            let free = remaining.filter { candidate in
                !remaining.contains { $0.routedThrough == candidate.id }
            }
            guard !free.isEmpty else {
                ordered.append(contentsOf: remaining)
                break
            }
            ordered.append(contentsOf: free)
            let done = Set(free.map(\.id))
            remaining.removeAll { done.contains($0.id) }
        }
        return ordered
    }

    static func nodeID(for deployment: UUID, slot: DeploymentNode.LegacySlot) -> UUID {
        var bytes = withUnsafeBytes(of: deployment.uuid) { Array($0) }
        bytes[15] ^= (slot == .vps ? 0x01 : 0x02)
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
