import Foundation
import ServiceCatalog

public enum MetricsIndicatorStyle: String, Codable, Sendable, Hashable, CaseIterable {
    case bars
    case track
    case rings
    /// Metric name + big value with a thin full-width underline
    case minimal
}

public struct Deployment: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    /// User-facing label, e.g
    public var name: String
    public var topology: Topology
    public var domain: String
    /// Further domains this server also answers on
    public var additionalDomains: [String]
    public var entry: HostEndpoint
    public var homeWGAddress: String?
    public var wgInterface: String
    public var services: Set<ServiceID>
    public var serviceSettings: ServiceSettings
    public var timeouts: OperationTimeouts
    public var tags: [String]
    /// Per-server load-indicator style; `nil` follows the app-level setting
    public var metricsIndicatorStyle: MetricsIndicatorStyle?
    public var usesPasswordAuth: Bool
    public var usesAgent: Bool
    /// Optional personalization
    public var iconSymbol: String?
    public var tintName: String?
    /// How big this server's card is drawn
    public var cardSize: ServerCardSize?
    /// Public-internet (default) or local-network-only — see `DeploymentScope`
    public var scope: DeploymentScope
    /// Machines beyond what `entry`/`homeWGAddress` can describe
    public var storedNodes: [DeploymentNode]?

    /// Which machine runs which service
    public var placement: ServicePlacement?

    public var wakeOnLANMAC: String?
    /// The broadcast address read from the machine
    public var wakeOnLANBroadcast: String?
    /// Runs the VPN on the relay instead of at home
    public var vpnOnRelay: Bool?
    /// Login on the home machine; `nil` reuses the entry user
    public var homeUser: String?
    /// Services closed on the relay
    public var homeOnlyServices: Set<ServiceID> = []
    /// Home-only services that VPN clients cannot open either
    public var homeOnlyNoVPN: Set<ServiceID> = []
    public var homeOnlyDNSRemoved: Set<ServiceID> = []

    public init(
        id: UUID = UUID(),
        name: String,
        topology: Topology,
        domain: String = "",
        additionalDomains: [String] = [],
        entry: HostEndpoint,
        homeWGAddress: String? = nil,
        wgInterface: String = "wg0",
        services: Set<ServiceID> = [],
        serviceSettings: ServiceSettings = ServiceSettings(),
        timeouts: OperationTimeouts = OperationTimeouts(),
        tags: [String] = [],
        metricsIndicatorStyle: MetricsIndicatorStyle? = nil,
        usesPasswordAuth: Bool = false,
        usesAgent: Bool = false,
        iconSymbol: String? = nil,
        tintName: String? = nil,
        cardSize: ServerCardSize? = nil,
        scope: DeploymentScope = .publicInternet,
        storedNodes: [DeploymentNode]? = nil,
        placement: ServicePlacement? = nil,
        wakeOnLANMAC: String? = nil,
        homeUser: String? = nil,
        homeOnlyServices: Set<ServiceID> = [],
        homeOnlyNoVPN: Set<ServiceID> = [],
        homeOnlyDNSRemoved: Set<ServiceID> = []
    ) {
        self.id = id
        self.name = name
        self.topology = topology
        self.domain = domain
        self.additionalDomains = additionalDomains
        self.entry = entry
        self.homeWGAddress = homeWGAddress
        self.wgInterface = wgInterface
        self.services = services
        self.serviceSettings = serviceSettings
        self.timeouts = timeouts
        self.tags = tags
        self.metricsIndicatorStyle = metricsIndicatorStyle
        self.usesPasswordAuth = usesPasswordAuth
        self.usesAgent = usesAgent
        self.iconSymbol = iconSymbol
        self.tintName = tintName
        self.cardSize = cardSize
        self.scope = scope
        self.storedNodes = storedNodes
        self.placement = placement
        self.wakeOnLANMAC = wakeOnLANMAC
        self.homeUser = homeUser
        self.homeOnlyServices = homeOnlyServices
        self.homeOnlyNoVPN = homeOnlyNoVPN
        self.homeOnlyDNSRemoved = homeOnlyDNSRemoved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        topology = try container.decode(Topology.self, forKey: .topology)
        domain = try container.decode(String.self, forKey: .domain)
        additionalDomains = try container.decodeIfPresent([String].self,
                                                          forKey: .additionalDomains) ?? []
        entry = try container.decode(HostEndpoint.self, forKey: .entry)
        homeWGAddress = try container.decodeIfPresent(String.self, forKey: .homeWGAddress)
        wgInterface = try container.decode(String.self, forKey: .wgInterface)
        services = try container.decode(Set<ServiceID>.self, forKey: .services)
        serviceSettings = try container.decode(ServiceSettings.self, forKey: .serviceSettings)
        timeouts = try container.decode(OperationTimeouts.self, forKey: .timeouts)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        metricsIndicatorStyle = try container.decodeIfPresent(
            MetricsIndicatorStyle.self, forKey: .metricsIndicatorStyle)
        usesPasswordAuth = try container.decodeIfPresent(Bool.self, forKey: .usesPasswordAuth) ?? false
        usesAgent = try container.decodeIfPresent(Bool.self, forKey: .usesAgent) ?? false
        iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol)
        tintName = try container.decodeIfPresent(String.self, forKey: .tintName)
        cardSize = try container.decodeIfPresent(ServerCardSize.self, forKey: .cardSize)
        scope = try container.decodeIfPresent(DeploymentScope.self, forKey: .scope) ?? .publicInternet
        storedNodes = try container.decodeIfPresent([DeploymentNode].self, forKey: .storedNodes)
        placement = try container.decodeIfPresent(ServicePlacement.self, forKey: .placement)
        wakeOnLANMAC = try container.decodeIfPresent(String.self, forKey: .wakeOnLANMAC)
        wakeOnLANBroadcast = try container.decodeIfPresent(String.self, forKey: .wakeOnLANBroadcast)
        vpnOnRelay = try container.decodeIfPresent(Bool.self, forKey: .vpnOnRelay)
        homeUser = try container.decodeIfPresent(String.self, forKey: .homeUser)
        homeOnlyServices = try container.decodeIfPresent(Set<ServiceID>.self, forKey: .homeOnlyServices) ?? []
        homeOnlyNoVPN = try container.decodeIfPresent(Set<ServiceID>.self, forKey: .homeOnlyNoVPN) ?? []
        homeOnlyDNSRemoved = try container.decodeIfPresent(Set<ServiceID>.self, forKey: .homeOnlyDNSRemoved) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(topology, forKey: .topology)
        try container.encode(domain, forKey: .domain)
        try container.encode(additionalDomains, forKey: .additionalDomains)
        try container.encode(entry, forKey: .entry)
        try container.encodeIfPresent(homeWGAddress, forKey: .homeWGAddress)
        try container.encode(wgInterface, forKey: .wgInterface)
        try container.encode(services, forKey: .services)
        try container.encode(serviceSettings, forKey: .serviceSettings)
        try container.encode(timeouts, forKey: .timeouts)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(metricsIndicatorStyle, forKey: .metricsIndicatorStyle)
        try container.encode(usesPasswordAuth, forKey: .usesPasswordAuth)
        try container.encode(usesAgent, forKey: .usesAgent)
        try container.encodeIfPresent(iconSymbol, forKey: .iconSymbol)
        try container.encodeIfPresent(tintName, forKey: .tintName)
        try container.encodeIfPresent(cardSize, forKey: .cardSize)
        try container.encode(scope, forKey: .scope)
        try container.encodeIfPresent(storedNodes, forKey: .storedNodes)
        try container.encodeIfPresent(placement, forKey: .placement)
        try container.encodeIfPresent(wakeOnLANMAC, forKey: .wakeOnLANMAC)
        try container.encodeIfPresent(wakeOnLANBroadcast, forKey: .wakeOnLANBroadcast)
        try container.encodeIfPresent(vpnOnRelay, forKey: .vpnOnRelay)
        try container.encodeIfPresent(homeUser, forKey: .homeUser)
        if !homeOnlyServices.isEmpty {
            try container.encode(homeOnlyServices, forKey: .homeOnlyServices)
        }
        if !homeOnlyNoVPN.isEmpty {
            try container.encode(homeOnlyNoVPN, forKey: .homeOnlyNoVPN)
        }
        if !homeOnlyDNSRemoved.isEmpty {
            try container.encode(homeOnlyDNSRemoved, forKey: .homeOnlyDNSRemoved)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, topology, domain, additionalDomains, entry, homeWGAddress, wgInterface
        case services, serviceSettings, timeouts, tags, metricsIndicatorStyle, usesPasswordAuth
        case usesAgent, iconSymbol, tintName, cardSize, scope, storedNodes, placement
        case wakeOnLANMAC, wakeOnLANBroadcast, vpnOnRelay, homeUser, homeOnlyServices
        case homeOnlyNoVPN, homeOnlyDNSRemoved
    }

    public var homeOnlyIDs: Set<String> { Set(homeOnlyServices.map(\.rawValue)) }

    public var effectiveHomeUser: String {
        homeUser.flatMap { $0.isEmpty ? nil : $0 } ?? entry.user
    }

    public var serviceContext: ServiceContext {
        ServiceContext(domain: domain, additionalDomains: additionalDomains,
                       sshUser: entry.user, settings: serviceSettings,
                       installedServices: services, usesInternalTLS: scope.usesInternalTLS)
    }

    /// Installed services in the registry's stable order
    public var installedServices: [any ManagedService] {
        ServiceRegistry.services(services)
    }

    public var isMultiHost: Bool { nodes.count > 1 }

    public var hasRelayIngress: Bool {
        nodes.contains { $0.terminatesPublicTraffic && !$0.runsServices }
    }

    /// A machine that can take a USB drive
    public var hasPhysicalAccess: Bool {
        topology == .vpsRelayWithHomeBackend || scope == .localOnly || scope == .dynamicDNS
    }

    /// A home machine whose services can leave the internet
    public var closesServicesAtHome: Bool {
        (hasHomeHost && hasRelayIngress) || scope == .dynamicDNS
    }

    public var hasHomeHost: Bool {
        nodes.contains { $0.routedThrough != nil && !$0.endpoint.host.isEmpty }
    }

    /// Every machine of this deployment that runs an agent
    public var agentHosts: [SSHHostID] {
        hasRelayIngress && servicesHost != .vps ? [servicesHost, .vps] : [servicesHost]
    }

    public var servicesHost: SSHHostID {
        (servicesNode ?? nodes.first)?.sshHost ?? .vps
    }
}

public struct HostEndpoint: Codable, Sendable, Hashable {
    public var host: String
    public var port: Int
    public var user: String

    public init(host: String, port: Int = 22, user: String) {
        self.host = host
        self.port = port
        self.user = user
    }

    public var isValid: Bool {
        !host.isEmpty && !user.isEmpty && (1...65535).contains(port)
    }
}

public struct OperationTimeouts: Codable, Sendable, Hashable {
    public var quickSeconds: Int
    public var restartSeconds: Int
    public var serviceRestartSeconds: Int
    /// Updates and backups — up to ten minutes
    public var longSeconds: Int

    public init(quickSeconds: Int = 15, restartSeconds: Int = 60,
                serviceRestartSeconds: Int = 120, longSeconds: Int = 600) {
        self.quickSeconds = quickSeconds
        self.restartSeconds = restartSeconds
        self.serviceRestartSeconds = serviceRestartSeconds
        self.longSeconds = longSeconds
    }

    public func duration(for timeoutClass: ServiceCommand.TimeoutClass) -> Duration {
        switch timeoutClass {
        case .quick: return .seconds(quickSeconds)
        case .restart: return .seconds(serviceRestartSeconds)
        case .long: return .seconds(longSeconds)
        }
    }
}

extension Deployment {
    public var dashboardConfig: DashboardConfig {
        DashboardConfig(
            vpsHost: entry.host,
            sshPort: entry.port,
            sshUser: entry.user,
            homeSSHUser: homeUser ?? "",
            homeWGAddress: homeWGAddress ?? "",
            wgInterface: wgInterface,
            mailcowPath: serviceSettings.mailcowPath,
            vaultwardenContainer: serviceSettings.vaultwardenContainer,
            vaultwardenDataPath: serviceSettings.vaultwardenDataPath,
            mailcowBackupDir: serviceSettings.mailcowBackupDir,
            vaultwardenBackupDir: serviceSettings.vaultwardenBackupDir,
            backupRetention: serviceSettings.backupRetention,
            quickTimeoutSeconds: timeouts.quickSeconds,
            restartTimeoutSeconds: timeouts.restartSeconds,
            mailcowRestartTimeoutSeconds: timeouts.serviceRestartSeconds,
            longTimeoutSeconds: timeouts.longSeconds
        )
    }
}
