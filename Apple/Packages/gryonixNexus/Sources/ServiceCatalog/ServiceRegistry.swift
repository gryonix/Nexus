/// Catalog of every service gryonixNexus can install and manage. Adding a
/// service = one ManagedService implementation + one entry here.
public enum ServiceRegistry {
    /// The members of `category` that this scope can actually run
    public static func services(in category: ServiceCategory,
                                scope: DeploymentScope) -> [any ManagedService] {
        services(in: category).filter { scope.carriesNonWebServices || !$0.requiresPublicDomain }
    }

    /// The same, minus add-ons whose hub is unticked
    public static func services(in category: ServiceCategory, scope: DeploymentScope,
                                selected: Set<ServiceID>) -> [any ManagedService] {
        services(in: category, scope: scope).filter { service in
            !ServiceID.smartHomeAddOns.contains(service.id) || selected.contains(.homeAssistant)
        }
    }

    public static let all: [any ManagedService] = [
        MailcowService(),
        MailuService(),
        DockerMailserverService(),
        VaultwardenService(),
        PsonoService(),
        PassboltService(),
        NextcloudService(),
        SeafileService(),
        ImmichService(),
        PhotoPrismService(),
        ForgejoService(),
        GitLabService(),
        JellyfinService(),
        AdGuardHomeService(),
        PiholeService(),
        HeadscaleService(),
        TailscaleNodeService(),
        CloudflaredService(),
        HomepageService(),
        AutheliaService(),
        WireGuardVPNService(),
        AmneziaWGVPNService(),
        ShadowsocksService(),
        XrayRealityService(),
        OpenVPNService(),
        VPNPanelService(),
        MinecraftJavaService(),
        MinecraftBedrockService(),
        CraftyControllerService(),
        OpenWebUIService(),
        OllamaService(),
        AnythingLLMService(),
        LiteLLMService(),
        QdrantService(),
        SearXNGService(),
        OpenClawService(),
        N8NService(),
        HomeAssistantService(),
        MosquittoService(),
        Zigbee2MQTTService()
    ]

    public static func expanded(_ selection: Set<ServiceID>,
                                scope: DeploymentScope,
                                modelBackend: ModelBackend) -> Set<ServiceID> {
        var ids = selection
        if !ids.isDisjoint(with: ServiceID.vpnProtocols) { ids.insert(.vpnPanel) }
        if scope == .cloudflareTunnel { ids.insert(.cloudflared) }
        if scope.requiresMesh { ids.insert(.headscale) }
        if !ids.isDisjoint(with: ServiceID.gameServers) { ids.insert(.craftyController) }
        // Zigbee publishes to the broker, so one brings both
        if ids.contains(.zigbee2MQTT) { ids.insert(.mosquitto) }
        if !ids.isDisjoint(with: ServiceID.modelConsumers), modelBackend.runsLocalEngine {
            ids.insert(.ollama)
        }
        if !ids.isDisjoint(with: ServiceID.modelConsumers), modelBackend == .external {
            ids.insert(.liteLLM)
        }
        if ids.contains(.headscale) { ids.insert(.tailscaleNode) }
        return ids
    }

    /// The categories that actually have members, in display order
    public static var categories: [ServiceCategory] {
        let present = Set(all.map(\.category))
        return ServiceCategory.selectable.filter { present.contains($0) }.sorted()
    }

    /// Members of a category, in the catalog's stable order
    public static func services(in category: ServiceCategory) -> [any ManagedService] {
        all.filter { $0.category == category }
    }

    public static func ids(in category: ServiceCategory) -> Set<ServiceID> {
        Set(services(in: category).map(\.id))
    }

    /// What a selection installs from one category, in catalog order
    public static func selection(in category: ServiceCategory,
                                 from selection: Set<ServiceID>) -> [ServiceID] {
        services(in: category).map(\.id).filter { selection.contains($0) }
    }

    /// Selectable mail engines, in catalog order
    public static var mailEngines: [any MailEngineService] {
        all.compactMap { $0 as? any MailEngineService }
    }

    /// Ids of every mail engine
    public static var mailEngineIDs: Set<ServiceID> {
        Set(mailEngines.map(\.id))
    }

    /// The mail engine in a selection, if any
    public static func mailEngine(in selection: Set<ServiceID>) -> ServiceID? {
        mailEngines.first { selection.contains($0.id) }?.id
    }

    public static func service(_ id: ServiceID) -> (any ManagedService)? {
        all.first { $0.id == id }
    }

    public static func services(_ ids: Set<ServiceID>) -> [any ManagedService] {
        // Stable order for deterministic script/UI output.
        all.filter { ids.contains($0.id) }
    }

    /// Conflicting pairs inside a selection (e.g
    public static func conflicts(in selection: Set<ServiceID>) -> [(ServiceID, ServiceID)] {
        var result: [(ServiceID, ServiceID)] = []
        for service in services(selection) {
            for other in service.conflicts.intersection(selection) where service.id < other {
                result.append((service.id, other))
            }
        }
        return result
    }

    /// A relay: WireGuard, firewall, CrowdSec and metrics, no services
    public static let relayRequirements = ServerRequirements(memoryMB: 512, diskGB: 2, installsDocker: false)

    /// The minimum server the selected services need
    public static func requirements(for selection: Set<ServiceID>) -> ServerRequirements {
        let baseMemoryMB = 512
        let baseDiskGB = 4
        let selected = services(selection)
        let memoryMB = baseMemoryMB + selected.reduce(0) { $0 + $1.resources.memoryMB }
        let diskGB = baseDiskGB + selected.reduce(0) { $0 + $1.resources.diskGB }
        return ServerRequirements(memoryMB: memoryMB, diskGB: diskGB,
                                  installsDocker: needsDocker(selection))
    }

    public static func needsDocker(_ selection: Set<ServiceID>) -> Bool {
        services(selection).contains { service in
            if case .docker = service.runtime { return true }
            return false
        }
    }
}
