import AgentClient
import Foundation
import ServerControl
import ServiceCatalog

public struct AgentModOperations: Sendable {
    /// The one service that takes mods today
    public static let serviceID = ServiceID.minecraftJava.rawValue

    private let client: AgentClient
    private let gate: AgentChannelGate?

    public init(client: AgentClient, gate: AgentChannelGate? = nil) {
        self.client = client
        self.gate = gate
    }

    public static func loader(forFlavour flavour: String) -> String? {
        switch flavour.uppercased() {
        case "FABRIC": return "fabric"
        case "FORGE": return "forge"
        case "NEOFORGE": return "neoforge"
        case "QUILT": return "quilt"
        case "PAPER": return "paper"
        case "PURPUR": return "purpur"
        case "SPIGOT": return "spigot"
        case "BUKKIT": return "bukkit"
        default: return nil
        }
    }

    public static func slot(forFlavour flavour: String) -> Gryonixnexusd_V1_ModSlot {
        switch flavour.uppercased() {
        case "PAPER", "PURPUR", "SPIGOT", "BUKKIT": return .plugins
        default: return .mods
        }
    }

    public func search(query: String,
                       gameVersion: String,
                       loader: String,
                       limit: UInt32 = 0,
                       offset: UInt32 = 0) async throws -> Gryonixnexusd_V1_ModSearchResult {
        try await mapping {
            try await client.searchMods(serviceID: Self.serviceID,
                                        query: query,
                                        gameVersion: gameVersion,
                                        loader: loader,
                                        limit: limit,
                                        offset: offset)
        }
    }

    public func versions(project: String,
                         gameVersion: String,
                         loader: String) async throws -> [Gryonixnexusd_V1_ModVersion] {
        try await mapping {
            try await client.modVersions(serviceID: Self.serviceID,
                                         project: project,
                                         gameVersion: gameVersion,
                                         loader: loader).versions
        }
    }

    public func files() async throws -> Gryonixnexusd_V1_ModFileList {
        try await mapping { try await client.listModFiles(serviceID: Self.serviceID) }
    }

    @discardableResult
    public func upload(name: String,
                       slot: Gryonixnexusd_V1_ModSlot,
                       content: Data) async throws -> Gryonixnexusd_V1_ModFileList {
        try await mapping {
            try await client.uploadModFile(serviceID: Self.serviceID,
                                           slot: slot,
                                           name: name,
                                           content: content)
        }
    }

    @discardableResult
    public func delete(name: String, slot: Gryonixnexusd_V1_ModSlot) async throws -> Gryonixnexusd_V1_ModFileList {
        try await mapping {
            try await client.deleteModFile(serviceID: Self.serviceID, slot: slot, name: name)
        }
    }

    public static func entry(slug: String, versionID: String) -> String {
        versionID.isEmpty ? slug : "\(slug):\(versionID)"
    }

    /// The stored list, as a list
    public static func entries(in setting: String) -> [String] {
        setting.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The setting text for a list of entries
    public static func setting(from entries: [String]) -> String {
        entries.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
    }

    public static func slug(ofEntry entry: String) -> String {
        String(entry.split(separator: ":").first ?? "")
    }

    // MARK: - Helpers

    private func mapping<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        do {
            guard let gate else { return try await body() }
            return try await gate.withSlot(body)
        } catch let error as AgentError {
            guard case .rpc(_, let message) = error, !message.isEmpty else { throw error }
            throw ServerControlError.commandFailed(command: "mods", exitCode: nil, stderr: message)
        }
    }
}
