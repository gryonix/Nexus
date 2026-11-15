import Foundation

/// Agent updates still running, kept across app launches
struct PendingAgentUpdates {
    struct Entry: Codable, Equatable {
        let deploymentID: UUID
        let installed: String
        let target: String
        let source: AgentUpdateOffer.Outdated.Source
        var startedAt = Date()

        init(deploymentID: UUID, installed: String, target: String,
             source: AgentUpdateOffer.Outdated.Source, startedAt: Date = Date()) {
            self.deploymentID = deploymentID
            self.installed = installed
            self.target = target
            self.source = source
            self.startedAt = startedAt
        }

        init(_ server: AgentUpdateOffer.Outdated) {
            self.init(deploymentID: server.id, installed: server.installed,
                      target: server.target, source: server.source)
        }
    }

    /// Older than this, the update is given up on
    static let keptFor: TimeInterval = 6 * 3600
    static let key = "agentUpdate.pending"

    var defaults: UserDefaults = .standard
    var now: () -> Date = Date.init

    func load() -> [Entry] {
        guard let data = defaults.data(forKey: Self.key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries.filter { now().timeIntervalSince($0.startedAt) < Self.keptFor }
    }

    func add(_ entries: [Entry]) {
        let fresh = Set(entries.map(\.deploymentID))
        save(load().filter { !fresh.contains($0.deploymentID) } + entries)
    }

    func remove(_ deploymentID: UUID) {
        save(load().filter { $0.deploymentID != deploymentID })
    }

    /// Forgets servers that are gone
    func keep(_ deploymentIDs: Set<UUID>) {
        save(load().filter { deploymentIDs.contains($0.deploymentID) })
    }

    private func save(_ entries: [Entry]) {
        if entries.isEmpty {
            defaults.removeObject(forKey: Self.key)
        } else if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
