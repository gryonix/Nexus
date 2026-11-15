import AgentControl
import Foundation

/// Edits of the DNS relay's resolver order
enum VPNDNSPriorityEditing {
    static let maxResolvers = 4

    /// Public resolvers offered for the order, by first address
    static let publicChoices: [PublicDNS] = {
        var seen = Set<String>()
        return PublicDNS.all.filter { $0.variant == nil && seen.insert($0.provider).inserted }
    }()

    /// The order entry for the devices' chosen DNS
    static func chosenEntry(for dns: [String], localAddress: String) -> String {
        guard let first = dns.lazy.map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty })
        else { return "1.1.1.1" }
        if first == localAddress || first == LocalDNS.serverAddress || first == VPNDNSPriority.local {
            return VPNDNSPriority.local
        }
        return first
    }

    /// The order with this entry first and nowhere else
    static func pin(_ order: [String], first: String) -> [String] {
        Array(([first] + order.filter { $0 != first }).prefix(maxResolvers))
    }

    /// The first entry is the chosen DNS and stays put
    static func canMoveUp(_ index: Int) -> Bool { index > 1 }

    static func canMoveDown(_ index: Int, in order: [String]) -> Bool { index > 0 && index < order.count - 1 }

    static func moveUp(_ index: Int, in order: [String]) -> [String] {
        guard order.indices.contains(index), canMoveUp(index) else { return order }
        var moved = order
        moved.swapAt(index, index - 1)
        return moved
    }

    static func moveDown(_ index: Int, in order: [String]) -> [String] {
        guard order.indices.contains(index), canMoveDown(index, in: order) else { return order }
        var moved = order
        moved.swapAt(index, index + 1)
        return moved
    }

    /// The order without this entry; the chosen one stays
    static func remove(_ index: Int, from order: [String]) -> [String] {
        guard order.indices.contains(index), index > 0 else { return order }
        var trimmed = order
        trimmed.remove(at: index)
        return trimmed
    }

    /// The order with one more resolver at the end
    static func add(_ entry: String, to order: [String]) -> [String] {
        let clean = entry.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, !order.contains(clean), order.count < maxResolvers else { return order }
        return order + [clean]
    }

    static func canAdd(to order: [String]) -> Bool {
        order.count < maxResolvers
    }

    /// What one entry is called in the list
    static func name(of entry: String, local: LocalDNS) -> String {
        if entry == VPNDNSPriority.local { return local.services.isEmpty ? UIL10n.string("This server's DNS") : local.name }
        guard let preset = PublicDNS.all.first(where: { $0.addresses.contains(entry) }) else { return entry }
        return UIL10n.string("%@ (%@)", preset.name, entry)
    }
}
