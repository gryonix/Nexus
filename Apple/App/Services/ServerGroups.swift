import Foundation
import ServerControl

enum ServerGroups {
    /// Where the strip's group order is kept
    static let orderKey = "servers.groupOrder"

    static func known(in deployments: [Deployment],
                      order: [String] = storedOrder()) -> [String] {
        ordered(Array(Set(deployments.flatMap(\.tags))), by: order)
    }

    static func known() -> [String] {
        known(in: (try? FileDeploymentStore().load()) ?? [])
    }

    static func setting(_ member: Bool, of group: String, in tags: [String]) -> [String] {
        var result = tags.filter { $0.caseInsensitiveCompare(group) != .orderedSame }
        if member { result.append(group) }
        return result
    }

    /// Every server that carries this group
    static func members(of group: String, in deployments: [Deployment]) -> [Deployment] {
        deployments.filter { $0.tags.contains { $0.caseInsensitiveCompare(group) == .orderedSame } }
    }

    /// Servers in any of these groups, each once
    static func members(ofAny groups: [String], in deployments: [Deployment]) -> [Deployment] {
        deployments.filter { deployment in
            deployment.tags.contains { tag in contains(groups, tag) }
        }
    }

    static func clean(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Order

    /// Placed groups first, in order, then the rest by name
    static func ordered(_ groups: [String], by order: [String]) -> [String] {
        groups.sorted { left, right in
            switch (index(of: left, in: order), index(of: right, in: order)) {
            case let (l?, r?): return l < r
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return left < right
            }
        }
    }

    static func storedOrder(defaults: UserDefaults = .standard) -> [String] {
        parse(defaults.string(forKey: orderKey) ?? "")
    }

    static func parse(_ raw: String) -> [String] {
        raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    static func format(_ order: [String]) -> String {
        order.joined(separator: "\n")
    }

    /// The order after moving one group a place along
    static func moving(_ group: String, by offset: Int, among groups: [String],
                       stored: [String]) -> [String]? {
        var order = ordered(groups, by: stored)
        guard let from = index(of: group, in: order) else { return nil }
        let to = from + offset
        guard order.indices.contains(to) else { return nil }
        order.swapAt(from, to)
        return order + stored.filter { !contains(order, $0) }
    }

    static func renaming(_ old: String, to new: String, in stored: [String]) -> [String] {
        stored.map { $0.caseInsensitiveCompare(old) == .orderedSame ? new : $0 }
    }

    static func removing(_ group: String, from stored: [String]) -> [String] {
        stored.filter { $0.caseInsensitiveCompare(group) != .orderedSame }
    }

    /// Groups new to this device join at the end
    static func adopting(_ incoming: [String], into stored: [String]) -> [String] {
        stored + incoming.filter { !contains(stored, $0) }
    }

    private static func index(of group: String, in order: [String]) -> Int? {
        order.firstIndex { $0.caseInsensitiveCompare(group) == .orderedSame }
    }

    private static func contains(_ groups: [String], _ group: String) -> Bool {
        index(of: group, in: groups) != nil
    }
}

/// Groups and their servers, in one file
struct ServerGroupBundle: Codable {
    static let kind = "gryonixgroups"
    static let currentVersion = 1

    var kind = ServerGroupBundle.kind
    var version = currentVersion
    /// Group names, in the exporting device's order
    var groups: [String]
    var servers: [DeploymentTransfer]

    init(groups: [String], servers: [DeploymentTransfer]) {
        self.groups = groups
        self.servers = servers
    }

    enum BundleError: LocalizedError {
        case unsupportedVersion

        var errorDescription: String? {
            UIL10n.string("This file was exported by a newer version of the app. Update the app and try again.")
        }
    }

    private struct Probe: Decodable {
        var kind: String?
    }

    /// True for a group file, false for a single server
    static func isBundle(_ data: Data) -> Bool {
        (try? JSONDecoder().decode(Probe.self, from: data))?.kind == kind
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> ServerGroupBundle {
        let bundle = try JSONDecoder().decode(ServerGroupBundle.self, from: data)
        guard bundle.version <= currentVersion,
              bundle.servers.allSatisfy({ $0.version <= DeploymentTransfer.currentVersion })
        else { throw BundleError.unsupportedVersion }
        return bundle
    }

    /// Each server keeps only the groups this file carries
    static func make(groups: [String], transfers: [DeploymentTransfer]) -> ServerGroupBundle {
        let servers = transfers.map { transfer -> DeploymentTransfer in
            var trimmed = transfer
            trimmed.deployment.tags = transfer.deployment.tags.filter { tag in
                groups.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
            }
            return trimmed
        }
        return ServerGroupBundle(groups: groups, servers: servers)
    }

    static func fileName(for groups: [String]) -> String {
        let base = groups.count == 1 ? groups[0] : UIL10n.string("Server groups")
        let safe = base.replacingOccurrences(of: "/", with: "-")
        return "\(safe.isEmpty ? "groups" : safe).\(DeploymentTransferService.fileExtension)"
    }
}
