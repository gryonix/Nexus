import Foundation
import os
import VPNProfile

public enum SharedContainer {
    /// The group the app, widgets and tunnel share
    public static let appGroupIdentifier: String? = AppGroup.identifier

    /// Files this container held before the group existed
    static let sharedFileNames = ["vpn-profiles.json", "fleet-snapshot.json", "vpn-sessions.json"]

    public static var isShared: Bool { resolvedGroupURL != nil }

    /// The directory every shared file sits in
    public static var directory: URL {
        if let group = resolvedGroupURL, ensureExists(group) {
            adoptLegacyFiles(into: group)
            return group
        }
        ensureExists(applicationSupport)
        return applicationSupport
    }

    /// Creates the directory, logging the system's refusal
    @discardableResult
    static func ensureExists(_ directory: URL) -> Bool {
        let files = FileManager.default
        if files.fileExists(atPath: directory.path) { return true }
        do {
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            return true
        } catch {
            log.error("cannot create \(directory.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private static let log = Logger(subsystem: "com.skaymer.gryonixnexus", category: "tunnel")

    /// Moves files written before the group into it, once each
    static func adoptLegacyFiles(into group: URL, from legacy: URL = applicationSupport) {
        let files = FileManager.default
        for name in sharedFileNames {
            let old = legacy.appendingPathComponent(name)
            let new = group.appendingPathComponent(name)
            guard files.fileExists(atPath: old.path), !files.fileExists(atPath: new.path) else { continue }
            try? files.moveItem(at: old, to: new)
        }
    }

    public static func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    private static var resolvedGroupURL: URL? {
        guard let appGroupIdentifier else { return nil }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    private static var applicationSupport: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("gryonixNexus", isDirectory: true)
    }
}

struct SharedJSONFile<Value: Codable & Sendable>: Sendable {
    let url: URL

    init(name: String) {
        self.url = SharedContainer.url(for: name)
    }

    init(url: URL) {
        self.url = url
    }

    func read() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(Value.self, from: data)
    }

    @discardableResult
    func write(_ value: Value) -> Bool {
        (try? store(value)) != nil
    }

    /// Writes, throwing the system's reason on failure
    func store(_ value: Value) throws {
        try Self.encoder.encode(value).write(to: url, options: .atomic)
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
