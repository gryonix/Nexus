import Foundation
import ServiceCatalog

/// Adding and removing machines, and moving a service between them
public extension Deployment {
    enum NodeEditError: Error, Equatable, Sendable {
        /// The address is empty, so nothing could be dialled
        case noAddress
        case unknownParent
        case parentLoop
        /// Removing this machine would leave others reachable only through it
        case stillAParent
        case lastWorker
    }

    /// Adds a machine
    mutating func addNode(_ node: DeploymentNode) throws {
        guard !node.endpoint.host.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw NodeEditError.noAddress
        }
        var updated = nodes
        if let parent = node.routedThrough {
            guard updated.contains(where: { $0.id == parent }) else { throw NodeEditError.unknownParent }
        }
        updated.removeAll { $0.id == node.id }
        updated.append(node)
        guard Self.parentChainsTerminate(in: updated) else { throw NodeEditError.parentLoop }
        storedNodes = updated
    }

    mutating func removeNode(_ id: UUID) throws {
        var updated = nodes
        guard updated.contains(where: { $0.id == id }) else { return }
        guard !updated.contains(where: { $0.routedThrough == id }) else {
            throw NodeEditError.stillAParent
        }
        let survivors = updated.filter { $0.id != id }
        guard survivors.contains(where: \.runsServices) else { throw NodeEditError.lastWorker }
        updated = survivors
        storedNodes = updated

        if var current = placement, !current.isEmpty {
            for (raw, node) in current.entries where node == id {
                current[ServiceID(rawValue: raw)] = nil
            }
            placement = current.isEmpty ? nil : current
        }
    }

    /// Puts one service on one machine
    mutating func place(_ service: ServiceID, on node: UUID?) {
        var current = placement ?? ServicePlacement()
        current[service] = node
        placement = current.isEmpty ? nil : current
    }

    /// True when no machine's parent chain loops
    private static func parentChainsTerminate(in nodes: [DeploymentNode]) -> Bool {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        for node in nodes {
            var seen: Set<UUID> = [node.id]
            var current = node.routedThrough
            while let id = current {
                if seen.contains(id) { return false }
                seen.insert(id)
                current = byID[id]?.routedThrough
            }
        }
        return true
    }
}
