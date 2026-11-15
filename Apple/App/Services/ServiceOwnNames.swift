import AgentControl
import Foundation
import ServerControl
import ServiceCatalog

/// Names given to services, by server
@MainActor
final class ServiceOwnNames: ObservableObject {
    static let shared = ServiceOwnNames()
    static let namesKey = "serviceNames.byServer"
    static let unsentKey = "serviceNames.unsent"
    static let maxLength = 60

    private let local: UserDefaults

    init(local: UserDefaults = .standard) {
        self.local = local
    }

    /// Names of one server, by service id
    func names(server: String) -> [String: String] {
        all[server] ?? [:]
    }

    func name(_ service: ServiceID, server: UUID) -> String? {
        all[server.uuidString]?[service.rawValue]
    }

    /// The given name, or the catalog one
    func title(_ service: any ManagedService, server: UUID) -> String {
        name(service.id, server: server) ?? service.displayName
    }

    /// A service's given name, unless the group has its own
    func title(ofGroup group: ContainerGroup, server: UUID) -> String {
        guard !group.isRenamed, let agentID = group.serviceID else { return group.displayName }
        let services = AgentServiceMapping.serviceIDs(forAgentIDs: [agentID])
        guard services.count == 1, let service = services.first,
              let given = name(service, server: server) else { return group.displayName }
        return given
    }

    /// The stored name, readable off the main actor
    nonisolated static func storedName(service: String, server: UUID, in defaults: UserDefaults = .standard) -> String? {
        guard let data = defaults.data(forKey: "serviceNames.byServer"),
              let all = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return nil }
        return all[server.uuidString]?[service]
    }

    /// Servers whose names the agent has not taken
    var unsent: Set<String> {
        Set(local.stringArray(forKey: Self.unsentKey) ?? [])
    }

    /// Takes the server's own set as the truth
    func adopt(server: String, names: [String: String]) {
        var stored = all
        let kept = names.filter { !$0.value.isEmpty }
        markSent(server)
        guard stored[server] ?? [:] != kept else { return }
        objectWillChange.send()
        stored[server] = kept.isEmpty ? nil : kept
        store(stored)
    }

    /// Names a service here; empty puts the catalog name back
    func set(_ name: String, service: ServiceID, server: String, sent: Bool) {
        objectWillChange.send()
        var stored = all
        var names = stored[server] ?? [:]
        let cleaned = Self.cleaned(name)
        names[service.rawValue] = cleaned.isEmpty ? nil : cleaned
        stored[server] = names.isEmpty ? nil : names
        store(stored)
        if !sent { local.set(Array(unsent.union([server])).sorted(), forKey: Self.unsentKey) }
    }

    static func cleaned(_ name: String) -> String {
        let flat = name.components(separatedBy: .controlCharacters).joined(separator: " ")
        return String(flat.trimmingCharacters(in: .whitespaces).prefix(maxLength))
            .trimmingCharacters(in: .whitespaces)
    }

    private func markSent(_ server: String) {
        guard unsent.contains(server) else { return }
        local.set(Array(unsent.subtracting([server])).sorted(), forKey: Self.unsentKey)
    }

    private var all: [String: [String: String]] {
        guard let data = local.data(forKey: Self.namesKey),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return decoded
    }

    private func store(_ names: [String: [String: String]]) {
        local.set(try? JSONEncoder().encode(names), forKey: Self.namesKey)
    }
}
