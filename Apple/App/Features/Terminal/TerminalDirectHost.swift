import Foundation
import ServerControl

struct TerminalDirectHost: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    /// What the list shows
    var name: String
    var host: String
    var port: Int
    /// The account this connection signs in as
    var username: String

    init(id: UUID = UUID(), name: String = "", host: String, port: Int = 22,
         username: String) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
    }

    /// The name, or the address when there is no name
    var title: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? host : trimmed
    }

    var deployment: Deployment {
        Deployment(id: id,
                   name: title,
                   topology: .singleHost,
                   entry: HostEndpoint(host: host, port: port, user: username))
    }
}

/// The saved direct hosts, in a plain JSON file
struct TerminalDirectHostStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
            let directory = support.appendingPathComponent("gryonixNexus", isDirectory: true)
            AppSupportDirectory.adoptLegacyName(at: directory, legacyName: "GryonixNexus")
            self.fileURL = directory.appendingPathComponent("terminal-hosts.json")
        }
    }

    func load() throws -> [TerminalDirectHost] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return try JSONDecoder().decode([TerminalDirectHost].self,
                                        from: Data(contentsOf: fileURL))
    }

    func save(_ hosts: [TerminalDirectHost]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try JSONEncoder().encode(hosts).write(to: fileURL, options: .atomic)
    }

    func upsert(_ host: TerminalDirectHost) throws {
        var hosts = try load()
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = host
        } else {
            hosts.append(host)
        }
        try save(hosts)
    }

    func remove(id: UUID) throws {
        try save(try load().filter { $0.id != id })
    }
}
