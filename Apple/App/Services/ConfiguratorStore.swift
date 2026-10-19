import Foundation
import gryonixNexusCore
import ServerControl
import ServiceCatalog

/// One snapshot of the configurator form
struct ConfiguratorDraft: Codable, Identifiable, Hashable {
    var id = UUID()
    var savedAt = Date()
    var topology: Topology

    var domain = ""
    var reverseDNSHostname = ""
    /// Absent in drafts written before it existed
    var additionalDomains: [String] = []
    /// Public-internet (false, default) or local-network-only (true) — see `DeploymentScope`
    var localOnly = false
    /// The reachability scope — public, local-only, or through a tunnel
    var scope: DeploymentScope?
    var publicIP = ""
    var vpsVPNIP = "10.8.0.1"
    var homeVPNIP = "10.8.0.2"
    var distribution = DistributionProfileID.debian.rawValue
    /// Scenario B only: the home server's own distribution
    var homeDistribution: String?

    var mailEnabled = false
    /// Which mail engine the "Mail" toggle installs
    var mailEngineID: String = ServiceID.mailcow.rawValue
    var extraServices: Set<ServiceID> = []
    var vpnEnabled = false
    var vpnProtocols: Set<ServiceID> = []

    var serviceHostnames: [String: String]?
    var vaultwardenHostname = ""
    var vaultwardenAllowSignups = false
    var nextcloudHostname = ""
    /// Pi-hole's one consequential knob — see `ServiceSettings.piholeServesNetwork`
    var piholeServesNetwork: Bool?
    /// Which services SSO guards
    var autheliaProtectedServices: Set<ServiceID>?
    var minecraftJavaVersion: String?
    var minecraftJavaFlavour: String?
    var minecraftJavaMemoryMB: String?
    var minecraftJavaPort: String?
    var minecraftJavaAcceptsEULA: Bool?
    var minecraftJavaWhitelist: String?
    var minecraftJavaOperators: String?
    /// Modrinth entries, comma separated, as the mod browser wrote them
    var minecraftJavaMods: String?
    var minecraftBedrockVersion: String?
    var minecraftBedrockPort: String?
    var minecraftBedrockAcceptsEULA: Bool?
    var machineAtHome: Bool?
    var homeAssistantUSBDevice: String?
    var openWebUIAllowSignups: Bool?
    var ollamaUsesGPU: Bool?
    var ollamaInstallsGPUDriver: Bool?
    /// `ModelBackend.rawValue`
    var modelBackend: String?
    var adminUsername = "admin"
    var immichHostname = ""
    var forgejoHostname = ""
    var forgejoSSHPort = ""
    var gitlabHostname = ""
    var gitlabSSHPort = ""
    var vpnHostname = ""
    /// `VPNClientAccess.rawValue`
    var vpnClientAccess: String?
    var wireguardVPNPort = ""
    var amneziaWGPort = ""
    var shadowsocksPort = ""
    var xrayRealityPort = ""
    var xrayRealitySNI = ""
    var openVPNPort = ""

    var includeDashboardAccess = false
    var crowdsecEnabled: Bool?
    var dashboardSSHUser = ""
    var useExistingUser = false
    var deploymentID: UUID?
}

extension ConfiguratorDraft {
    private static let legacyHostnameFields: [ServiceID: WritableKeyPath<ConfiguratorDraft, String>] = [
        .vaultwarden: \.vaultwardenHostname,
        .nextcloud: \.nextcloudHostname,
        .immich: \.immichHostname,
        .forgejo: \.forgejoHostname,
        .gitlab: \.gitlabHostname,
    ]

    /// Every per-service hostname this draft carries
    var resolvedHostnames: [ServiceID: String] {
        var result: [ServiceID: String] = [:]
        for (id, keyPath) in Self.legacyHostnameFields where !self[keyPath: keyPath].isEmpty {
            result[id] = self[keyPath: keyPath]
        }
        for (raw, value) in serviceHostnames ?? [:] where !value.isEmpty {
            result[ServiceID(rawValue: raw)] = value
        }
        return result
    }

    /// Stores them both ways — see `serviceHostnames`
    mutating func setHostnames(_ hostnames: [ServiceID: String]) {
        serviceHostnames = Dictionary(uniqueKeysWithValues:
            hostnames.map { ($0.key.rawValue, $0.value) })
        for (id, keyPath) in Self.legacyHostnameFields {
            self[keyPath: keyPath] = hostnames[id] ?? ""
        }
    }

    var entryDistribution: DistributionProfileID {
        DistributionProfileID(rawValue: distribution) ?? .debian
    }

    /// Distribution of the home server
    var homeDistributionID: DistributionProfileID {
        homeDistribution.flatMap(DistributionProfileID.init(rawValue:)) ?? entryDistribution
    }

    init(recovering deployment: Deployment) {
        self.init(topology: deployment.topology)
        deploymentID = deployment.id
        domain = deployment.domain
        additionalDomains = deployment.additionalDomains
        localOnly = deployment.scope == .localOnly
        scope = deployment.scope
        publicIP = deployment.entry.host
        if let home = deployment.homeWGAddress, !home.isEmpty {
            homeVPNIP = home
        }
        selectServices(deployment.services)
        adopt(deployment.serviceSettings)
        includeDashboardAccess = true
        dashboardSSHUser = deployment.entry.user
        useExistingUser = deployment.usesPasswordAuth
    }
}

extension ConfiguratorDraft {
    /// Copies the answers a deployment record cannot give back
    mutating func carryUnrecoverable(from saved: ConfiguratorDraft) {
        reverseDNSHostname = saved.reverseDNSHostname
        vpsVPNIP = saved.vpsVPNIP
        distribution = saved.distribution
        homeDistribution = saved.homeDistribution
    }

    mutating func adopt(_ settings: ServiceSettings) {
        setHostnames(settings.namedHostnames)
        adoptPorts(settings)
        adoptGames(settings)
        vpnHostname = settings.vpnHostname
        vpnClientAccess = settings.vpnClientAccess.rawValue
        adminUsername = settings.adminUsername
        xrayRealitySNI = settings.xrayRealitySNI
        vaultwardenAllowSignups = settings.vaultwardenAllowSignups
        piholeServesNetwork = settings.piholeServesNetwork
        autheliaProtectedServices = settings.autheliaProtectedServices
        machineAtHome = settings.machineAtHome
        homeAssistantUSBDevice = settings.homeAssistantUSBDevice
        openWebUIAllowSignups = settings.openWebUIAllowSignups
        ollamaUsesGPU = settings.ollamaUsesGPU
        ollamaInstallsGPUDriver = settings.ollamaInstallsGPUDriver
        modelBackend = settings.modelBackend.rawValue
        crowdsecEnabled = settings.crowdsecEnabled
    }

    private mutating func adoptPorts(_ settings: ServiceSettings) {
        forgejoSSHPort = String(settings.forgejoSSHPort)
        gitlabSSHPort = String(settings.gitlabSSHPort)
        wireguardVPNPort = String(settings.wireguardVPNPort)
        amneziaWGPort = String(settings.amneziaWGPort)
        shadowsocksPort = String(settings.shadowsocksPort)
        xrayRealityPort = String(settings.xrayRealityPort)
        openVPNPort = String(settings.openVPNPort)
    }

    private mutating func adoptGames(_ settings: ServiceSettings) {
        minecraftJavaVersion = settings.minecraftJavaVersion
        minecraftJavaFlavour = settings.minecraftJavaFlavour
        minecraftJavaMemoryMB = String(settings.minecraftJavaMemoryMB)
        minecraftJavaPort = String(settings.minecraftJavaPort)
        minecraftJavaAcceptsEULA = settings.minecraftJavaAcceptsEULA
        minecraftJavaWhitelist = settings.minecraftJavaWhitelist
        minecraftJavaOperators = settings.minecraftJavaOperators
        minecraftJavaMods = settings.minecraftJavaMods
        minecraftBedrockVersion = settings.minecraftBedrockVersion
        minecraftBedrockPort = String(settings.minecraftBedrockPort)
        minecraftBedrockAcceptsEULA = settings.minecraftBedrockAcceptsEULA
    }

    init(reinstalling deployment: Deployment, saved: ConfiguratorDraft?) {
        self.init(recovering: deployment)
        if let saved { carryUnrecoverable(from: saved) }
        adoptDistributions(of: deployment)
    }

    /// The distribution each machine reports, where the record knows it
    mutating func adoptDistributions(of deployment: Deployment) {
        let entry = deployment.nodes.first(where: \.terminatesPublicTraffic)?.distribution
        let home = deployment.nodes.first(where: { $0.runsServices && !$0.terminatesPublicTraffic })?.distribution
        if let entry { distribution = entry }
        if let home { homeDistribution = home }
    }

    /// Selects exactly these installed services
    mutating func selectServices(_ services: Set<ServiceID>) {
        mailEnabled = ServiceRegistry.mailEngine(in: services) != nil
        mailEngineID = (ServiceRegistry.mailEngine(in: services) ?? .mailcow).rawValue
        vpnProtocols = services.intersection(ServiceID.vpnProtocols)
        vpnEnabled = !vpnProtocols.isEmpty
        extraServices = services
            .subtracting(ServiceID.vpnProtocols)
            .subtracting(ServiceRegistry.mailEngineIDs)
            .subtracting([.vpnPanel])
    }
}

final class ConfiguratorStore: @unchecked Sendable {
    static let shared = ConfiguratorStore()

    private let directory: URL
    private let historyLimit = 20

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
            let root = support.appendingPathComponent("gryonixNexus", isDirectory: true)
            AppSupportDirectory.adoptLegacyName(at: root, legacyName: "GryonixNexus")
            self.directory = root.appendingPathComponent("Configurator", isDirectory: true)
        }
    }

    func loadDraft(for topology: Topology, scope: DeploymentScope) -> ConfiguratorDraft? {
        guard let data = try? Data(contentsOf: draftURL(topology, scope)) else { return nil }
        return try? JSONDecoder().decode(ConfiguratorDraft.self, from: data)
    }

    func saveDraft(_ draft: ConfiguratorDraft) {
        write(draft, to: draftURL(draft.topology, draft.scope ?? (draft.localOnly ? .localOnly : .publicInternet)))
    }

    func clearDrafts() {
        for topology in Topology.allCases {
            for scope in DeploymentScope.allCases {
                try? FileManager.default.removeItem(at: draftURL(topology, scope))
            }
        }
    }

    func history() -> [ConfiguratorDraft] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        return (try? JSONDecoder().decode([ConfiguratorDraft].self, from: data)) ?? []
    }

    func appendToHistory(_ draft: ConfiguratorDraft) {
        var entry = draft
        entry.id = UUID()
        entry.savedAt = Date()
        var entries = history()
        entries.insert(entry, at: 0)
        write(Array(entries.prefix(historyLimit)), to: historyURL)
    }

    func deleteFromHistory(ids: Set<UUID>) {
        write(history().filter { !ids.contains($0.id) }, to: historyURL)
    }

    func loadDeploymentConfig(for id: UUID) -> ConfiguratorDraft? {
        guard let data = try? Data(contentsOf: deploymentConfigURL(id)) else { return nil }
        return try? JSONDecoder().decode(ConfiguratorDraft.self, from: data)
    }

    func saveDeploymentConfig(_ draft: ConfiguratorDraft) {
        guard let id = draft.deploymentID else { return }
        write(draft, to: deploymentConfigURL(id))
    }

    func deleteDeploymentConfig(for id: UUID) {
        try? FileManager.default.removeItem(at: deploymentConfigURL(id))
    }

    func configForReinstall(deploymentID: UUID) -> ConfiguratorDraft? {
        loadDeploymentConfig(for: deploymentID)
            ?? history().first { $0.deploymentID == deploymentID }
    }

    /// The last dashboard SSH username the user typed
    var lastDashboardUser: String? {
        get { UserDefaults.standard.string(forKey: "config-last-dashboard-user") }
        set {
            let key = "config-last-dashboard-user"
            if let value = newValue, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Files

    private func draftURL(_ topology: Topology, _ scope: DeploymentScope) -> URL {
        let suffix = scope == .publicInternet ? "" : "-\(scope.rawValue)"
        return directory.appendingPathComponent("draft-\(topology.rawValue)\(suffix).json")
    }

    private var historyURL: URL {
        directory.appendingPathComponent("history.json")
    }

    private func deploymentConfigURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("deployment-\(id.uuidString).json")
    }

    private func write(_ value: some Encodable, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            // Losing a draft must never interrupt the user's flow.
        }
    }
}
