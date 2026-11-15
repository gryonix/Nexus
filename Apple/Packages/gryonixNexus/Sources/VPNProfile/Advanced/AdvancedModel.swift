import Foundation

public struct AdvancedServer: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case vless, vmess, trojan, shadowsocks, wireguard, hysteria2, naive
    }

    public var id: String
    public var name: String
    public var kind: Kind
    public var host: String
    public var port: Int
    /// Protocol settings by name: uuid, password, method, network, sni...
    public var fields: [String: String]

    public init(kind: Kind, name: String, host: String, port: Int, fields: [String: String]) {
        self.kind = kind
        self.name = name.isEmpty ? host : name
        self.host = host
        self.port = port
        self.fields = fields
        self.id = Self.identity(kind: kind, host: host, port: port, fields: fields)
    }

    static func identity(kind: Kind, host: String, port: Int, fields: [String: String]) -> String {
        let secret = fields["uuid"] ?? fields["password"] ?? fields["secretKey"] ?? ""
        return "\(kind.rawValue)-\(host):\(port)-\(fnv(secret))"
    }

    static func fnv(_ text: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
        return String(hash, radix: 16)
    }
}

public struct AdvancedRule: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case domain, domainSuffix, keyword, ip, geoip
    }

    public enum Action: String, Codable, CaseIterable, Sendable {
        case direct, proxy, block
    }

    public var id: String
    public var kind: Kind
    public var value: String
    public var action: Action

    public init(id: String = UUID().uuidString, kind: Kind, value: String, action: Action) {
        self.id = id
        self.kind = kind
        self.value = value
        self.action = action
    }
}

public struct AdvancedGroup: Codable, Equatable, Identifiable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// The lowest-ping member is used
        case auto
        /// The chosen member is used
        case manual
    }

    public var id: String
    public var name: String
    public var mode: Mode
    public var memberIDs: [String]
    public var selectedID: String?

    public init(id: String = UUID().uuidString, name: String, mode: Mode,
                memberIDs: [String], selectedID: String? = nil) {
        self.id = id
        self.name = name
        self.mode = mode
        self.memberIDs = memberIDs
        self.selectedID = selectedID
    }

    /// The member a manual group sends traffic to
    public var chosenID: String? {
        selectedID.flatMap { memberIDs.contains($0) ? $0 : nil } ?? memberIDs.first
    }
}

public struct AdvancedDNSUpstream: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case plain, tcp, doh, doq, dot
    }

    public var id: String
    public var kind: Kind
    public var address: String
    /// Only these domains use this upstream; empty means all
    public var domains: [String]
    public var viaProxy: Bool

    public init(id: String = UUID().uuidString, kind: Kind, address: String,
                domains: [String] = [], viaProxy: Bool = true) {
        self.id = id
        self.kind = kind
        self.address = address
        self.domains = domains
        self.viaProxy = viaProxy
    }
}

public struct AdvancedBlockList: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var url: String
    public var domains: [String]
    public var updatedAt: Date?

    public init(id: String = UUID().uuidString, url: String, domains: [String] = [],
                updatedAt: Date? = nil) {
        self.id = id
        self.url = url
        self.domains = domains
        self.updatedAt = updatedAt
    }
}

public struct AdvancedSubscription: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var url: String
    public var serverIDs: [String]
    public var updatedAt: Date?

    public init(id: String = UUID().uuidString, name: String, url: String,
                serverIDs: [String] = [], updatedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.serverIDs = serverIDs
        self.updatedAt = updatedAt
    }
}

public struct AdvancedProfile: Codable, Equatable, Sendable {
    public var servers: [AdvancedServer] = []
    public var groups: [AdvancedGroup] = []
    public var rules: [AdvancedRule] = []
    public var finalAction: AdvancedRule.Action = .proxy
    public var dns: [AdvancedDNSUpstream] = []
    public var blockLists: [AdvancedBlockList] = []
    public var subscriptions: [AdvancedSubscription] = []
    /// A server id or a group id
    public var activeID: String?
    public var collectsTraffic = false
    public var geoip = AdvancedGeoIP()
    public var hosts: [AdvancedHostRewrite] = []
    /// Host rewrites apply only when this is on
    public var rewritesEnabled = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case servers, groups, rules, finalAction, dns, blockLists, subscriptions, activeID, collectsTraffic
        case geoip, hosts, rewritesEnabled
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        servers = try box.decodeIfPresent([AdvancedServer].self, forKey: .servers) ?? []
        groups = try box.decodeIfPresent([AdvancedGroup].self, forKey: .groups) ?? []
        rules = try box.decodeIfPresent([AdvancedRule].self, forKey: .rules) ?? []
        finalAction = try box.decodeIfPresent(AdvancedRule.Action.self, forKey: .finalAction) ?? .proxy
        dns = try box.decodeIfPresent([AdvancedDNSUpstream].self, forKey: .dns) ?? []
        blockLists = try box.decodeIfPresent([AdvancedBlockList].self, forKey: .blockLists) ?? []
        subscriptions = try box.decodeIfPresent([AdvancedSubscription].self, forKey: .subscriptions) ?? []
        activeID = try box.decodeIfPresent(String.self, forKey: .activeID)
        collectsTraffic = try box.decodeIfPresent(Bool.self, forKey: .collectsTraffic) ?? false
        geoip = try box.decodeIfPresent(AdvancedGeoIP.self, forKey: .geoip) ?? AdvancedGeoIP()
        hosts = try box.decodeIfPresent([AdvancedHostRewrite].self, forKey: .hosts) ?? []
        rewritesEnabled = try box.decodeIfPresent(Bool.self, forKey: .rewritesEnabled) ?? false
    }

    public func server(_ id: String) -> AdvancedServer? { servers.first { $0.id == id } }
    public func group(_ id: String) -> AdvancedGroup? { groups.first { $0.id == id } }

    /// The group or server the tunnel runs
    public var activeTarget: Target? {
        guard let activeID else { return nil }
        if let group = group(activeID) { return .group(group) }
        return server(activeID).map(Target.server)
    }

    public enum Target: Sendable {
        case server(AdvancedServer)
        case group(AdvancedGroup)
    }

    public func removing(serverIDs removed: Set<String>) -> AdvancedProfile {
        var copy = self
        copy.servers.removeAll { removed.contains($0.id) }
        for index in copy.groups.indices {
            copy.groups[index].memberIDs.removeAll { removed.contains($0) }
        }
        if let active = copy.activeID, copy.server(active) == nil, copy.group(active) == nil {
            copy.activeID = nil
        }
        return copy
    }

    /// Adds or replaces servers by id, keeping order
    public mutating func merge(servers incoming: [AdvancedServer]) {
        for server in incoming {
            if let index = servers.firstIndex(where: { $0.id == server.id }) {
                servers[index] = server
            } else {
                servers.append(server)
            }
        }
    }
}

/// What an import understood and what it left out.
public struct AdvancedImportReport: Equatable, Sendable {
    public struct Skipped: Error, Equatable, Sendable {
        public let name: String
        public let reason: String

        public init(name: String, reason: String) {
            self.name = name
            self.reason = reason
        }
    }

    public var servers: [AdvancedServer] = []
    public var rules: [AdvancedRule] = []
    public var unsupported: [Skipped] = []

    public init() {}

    public var isEmpty: Bool { servers.isEmpty && rules.isEmpty }
}
