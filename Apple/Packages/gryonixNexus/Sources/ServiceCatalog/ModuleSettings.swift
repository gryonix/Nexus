import Foundation

public enum AppModule: String, CaseIterable, Identifiable, Sendable {
    case ai
    case vpnAdvanced
    case portForwarding
    case scripts
    case dockerAdvanced

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ai: return "AI assistant"
        case .vpnAdvanced: return "VPN advanced settings"
        case .portForwarding: return "Port forwarding"
        case .scripts: return "Scripts"
        case .dockerAdvanced: return "Docker networks and system"
        }
    }

    public var isOnByDefault: Bool { false }

    public var isPerServer: Bool { self == .portForwarding || self == .dockerAdvanced }
}

@MainActor
public final class ModuleSettings: ObservableObject {
    public static let shared = ModuleSettings()

    private let local: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore?
    private var observer: NSObjectProtocol?

    public init(local: UserDefaults = .standard,
                cloud: NSUbiquitousKeyValueStore? = .default) {
        self.local = local
        self.cloud = cloud
        guard let cloud else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.adoptCloud() }
        }
        cloud.synchronize()
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public static func key(_ module: AppModule) -> String { "modules.\(module.rawValue)" }
    public static let serverSyncKey = "modules.serverSync"
    public static let serverSetsKey = "modules.serverSets"

    /// Modules are kept on each server's agent
    public var keptOnServers: Bool {
        get { local.object(forKey: Self.serverSyncKey) as? Bool ?? !AppModule.allCases.contains(where: localIsOn) }
        set {
            objectWillChange.send()
            local.set(newValue, forKey: Self.serverSyncKey)
        }
    }

    /// Last known set of each server, by deployment id
    public var serverSets: [String: Set<String>] {
        guard let data = local.data(forKey: Self.serverSetsKey),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return decoded.mapValues(Set.init)
    }

    /// On this device, or on any server when kept there
    public func isOn(_ module: AppModule) -> Bool {
        guard keptOnServers else { return localIsOn(module) }
        return serverSets.values.contains { $0.contains(module.rawValue) }
    }

    /// On for this server
    public func isOn(_ module: AppModule, server: String) -> Bool {
        guard keptOnServers else { return localIsOn(module) }
        return serverSets[server]?.contains(module.rawValue) ?? false
    }

    public func localIsOn(_ module: AppModule) -> Bool {
        local.object(forKey: Self.key(module)) as? Bool ?? module.isOnByDefault
    }

    public func adopt(server: String, on: Set<String>) {
        var sets = serverSets
        guard sets[server] != on else { return }
        objectWillChange.send()
        sets[server] = on
        store(sets)
    }

    public func forget(server: String) {
        var sets = serverSets
        guard sets.removeValue(forKey: server) != nil else { return }
        objectWillChange.send()
        store(sets)
    }

    @discardableResult
    public func set(_ module: AppModule, on: Bool, server: String) -> Set<String> {
        var set = serverSets[server] ?? []
        if on { set.insert(module.rawValue) } else { set.remove(module.rawValue) }
        adopt(server: server, on: set)
        return set
    }

    private func store(_ sets: [String: Set<String>]) {
        let plain = sets.mapValues { $0.sorted() }
        local.set(try? JSONEncoder().encode(plain), forKey: Self.serverSetsKey)
    }

    public func isOn(_ id: String) -> Bool {
        guard let module = AppModule(rawValue: id) else { return true }
        return isOn(module)
    }

    public func set(_ module: AppModule, on: Bool) {
        objectWillChange.send()
        local.set(on, forKey: Self.key(module))
        cloud?.set(on, forKey: Self.key(module))
    }

    private func adoptCloud() {
        guard let cloud else { return }
        objectWillChange.send()
        for module in AppModule.allCases {
            if let value = cloud.object(forKey: Self.key(module)) as? Bool {
                local.set(value, forKey: Self.key(module))
            }
        }
    }
}
