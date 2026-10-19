import Foundation

/// The tunnels this device has been given, on disk
public struct TunnelProfileStore: @unchecked Sendable {
    private let file: SharedJSONFile<[TunnelProfile]>
    /// Which profile the app brings up when nobody names one
    private let defaults: UserDefaults
    private static let selectedKey = "tunnel.selectedProfile"

    public init(defaults: UserDefaults = .standard) {
        self.file = SharedJSONFile(name: "vpn-profiles.json")
        self.defaults = defaults
    }

    /// For tests, which must not write into the real container
    public init(fileURL: URL, defaults: UserDefaults) {
        self.file = SharedJSONFile(url: fileURL)
        self.defaults = defaults
    }

    public func load() -> [TunnelProfile] {
        (file.read() ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    /// Adds, or replaces the profile describing the same tunnel
    @discardableResult
    public func save(_ profile: TunnelProfile) -> TunnelProfile {
        (try? store(profile)) ?? profile
    }

    /// Like `save`, throwing when the file cannot be written
    @discardableResult
    public func store(_ profile: TunnelProfile) throws -> TunnelProfile {
        var profiles = file.read() ?? []
        var stored = profile
        if let index = profiles.firstIndex(where: { $0.describesSameTunnel(as: profile) }) {
            stored = TunnelProfile(id: profiles[index].id,
                                   serverID: profile.serverID,
                                   serverName: profile.serverName,
                                   protocolID: profile.protocolID,
                                   deviceID: profile.deviceID,
                                   deviceName: profile.deviceName,
                                   endpoint: profile.endpoint,
                                   addresses: profile.addresses,
                                   dns: profile.dns,
                                   allowedIPs: profile.allowedIPs,
                                   mtu: profile.mtu,
                                   isObfuscated: profile.isObfuscated,
                                   createdAt: profile.createdAt)
            profiles[index] = stored
        } else {
            profiles.append(stored)
        }
        try file.store(profiles)
        if selectedID == nil { select(stored.id) }
        return stored
    }

    public func remove(id: UUID) {
        var profiles = file.read() ?? []
        profiles.removeAll { $0.id == id }
        file.write(profiles)
        if selectedID == id { select(profiles.first?.id) }
    }

    /// Every profile pointing at a server that is gone
    public func profiles(forServer serverID: UUID) -> [TunnelProfile] {
        load().filter { $0.serverID == serverID }
    }

    public var selectedID: UUID? {
        defaults.string(forKey: Self.selectedKey).flatMap(UUID.init(uuidString:))
    }

    public func select(_ id: UUID?) {
        if let id {
            defaults.set(id.uuidString, forKey: Self.selectedKey)
        } else {
            defaults.removeObject(forKey: Self.selectedKey)
        }
    }

    public func selected() -> TunnelProfile? {
        let profiles = load()
        if let selectedID, let match = profiles.first(where: { $0.id == selectedID }) {
            return match
        }
        return profiles.first
    }
}

/// Where a tunnel's actual credential lives
public protocol TunnelSecretStoring: Sendable {
    func secret(for account: String) -> String?
    func store(_ secret: String, for account: String) throws
    func delete(_ account: String)
}

/// The one used by tests and previews
public final class InMemoryTunnelSecretStore: TunnelSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [String: String] = [:]

    public init() {}

    public func secret(for account: String) -> String? {
        lock.withLock { secrets[account] }
    }

    public func store(_ secret: String, for account: String) throws {
        lock.withLock { secrets[account] = secret }
    }

    public func delete(_ account: String) {
        lock.withLock { secrets[account] = nil }
    }
}
