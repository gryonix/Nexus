/// Deployment-specific values a service needs to describe itself — paths,
/// container names, the ssh user for sudoers. Shared verbatim between the
/// generator (bakes them into scripts/sudoers) and the dashboard (builds the
/// same commands at runtime): both sides must read the same stored values or
/// sudo will reject the commands.
public struct ServiceContext: Sendable, Hashable, Codable {
    /// Mail/base domain, e.g
    public var domain: String
    /// Further domains this server also answers on
    public var additionalDomains: [String]
    /// Dashboard's ssh login on the server; the sudoers subject
    public var sshUser: String
    public var settings: ServiceSettings
    public var language: AppLanguage
    /// Every service being installed on this host
    public var installedServices: Set<ServiceID>
    /// Caddy signs its own certificate here
    public var usesInternalTLS: Bool

    public init(domain: String, additionalDomains: [String] = [], sshUser: String,
                settings: ServiceSettings = ServiceSettings(),
                language: AppLanguage = .en,
                installedServices: Set<ServiceID> = [],
                usesInternalTLS: Bool = false) {
        self.domain = domain
        self.additionalDomains = additionalDomains
        self.sshUser = sshUser
        self.settings = settings
        self.language = language
        self.installedServices = installedServices
        self.usesInternalTLS = usesInternalTLS
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        domain = try container.decode(String.self, forKey: .domain)
        additionalDomains = try container.decodeIfPresent([String].self, forKey: .additionalDomains) ?? []
        sshUser = try container.decode(String.self, forKey: .sshUser)
        settings = try container.decodeIfPresent(ServiceSettings.self, forKey: .settings) ?? ServiceSettings()
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .en
        installedServices = try container.decodeIfPresent(Set<ServiceID>.self, forKey: .installedServices) ?? []
        usesInternalTLS = try container.decodeIfPresent(Bool.self, forKey: .usesInternalTLS) ?? false
    }

    public func mirroredHostnames(of hostname: String) -> [String] {
        guard hostname.hasSuffix(".\(domain)") else { return [] }
        let prefix = String(hostname.dropLast(domain.count + 1))
        return additionalDomains.map { "\(prefix).\($0)" }
    }

    public func servedHostnames(of hostname: String) -> [String] {
        [hostname] + mirroredHostnames(of: hostname)
    }

    /// Where a service's backups live
    public func backupDirectory(for id: ServiceID) -> String {
        switch id {
        case .mailcow: return settings.mailcowBackupDir
        case .vaultwarden: return settings.vaultwardenBackupDir
        default: return "\(settings.backupRoot)/\(id.rawValue)"
        }
    }
}

/// Per-service knobs, all with working defaults
public struct ServiceSettings: Sendable, Hashable, Codable {
    // Mailcow
    public var mailcowPath: String
    public var mailcowBackupDir: String
    public var eraseMailOnDomainChange: Bool
    public var mailuPath: String
    /// Docker network the Mailu stack runs on
    public var mailuSubnet: String
    public var dockerMailserverPath: String
    // Vaultwarden
    public var vaultwardenContainer: String
    public var vaultwardenDataPath: String
    public var vaultwardenBackupDir: String
    /// Full web UI hostname; empty — vault.<domain>
    public var vaultwardenHostname: String
    /// Open registration; off — access only by invitation from /admin
    public var vaultwardenAllowSignups: Bool
    public var psonoPath: String
    /// Full hostname; empty — psono.<domain>
    public var psonoHostname: String
    public var passboltPath: String
    /// Full hostname; empty — passbolt.<domain>
    public var passboltHostname: String
    // Nextcloud
    public var nextcloudPath: String
    /// Full hostname; empty — cloud.<domain>
    public var nextcloudHostname: String
    /// Admin login, created on the container's first run
    public var nextcloudAdminUser: String
    public var seafilePath: String
    /// Full hostname; empty — files.<domain>
    public var seafileHostname: String
    // Immich
    public var immichPath: String
    /// Full hostname; empty — photos.<domain>
    public var immichHostname: String
    public var photoprismPath: String
    /// Full hostname; empty — photoprism.<domain>
    public var photoprismHostname: String
    // Jellyfin
    public var jellyfinPath: String
    /// Full hostname; empty — media.<domain>
    public var jellyfinHostname: String
    /// Where the media library lives
    public var jellyfinMediaPath: String
    public var minecraftJavaPath: String
    /// Game version, e.g
    public var minecraftJavaVersion: String
    /// Server flavour: VANILLA, PAPER, FABRIC, FORGE
    public var minecraftJavaFlavour: String
    /// Heap for the JVM
    public var minecraftJavaMemoryMB: Int
    public var minecraftJavaPort: Int
    /// Mojang's EULA, which the server refuses to start without
    public var minecraftJavaAcceptsEULA: Bool
    /// Player names allowed on, comma separated
    public var minecraftJavaWhitelist: String
    /// Player names with operator rights, comma separated
    public var minecraftJavaOperators: String
    public var minecraftJavaMods: String
    // Minecraft, Bedrock edition — phones, consoles and the Windows app.
    public var minecraftBedrockPath: String
    public var minecraftBedrockVersion: String
    public var minecraftBedrockPort: Int
    public var minecraftBedrockAcceptsEULA: Bool
    // Crafty Controller — the panel in front of the game servers.
    public var craftyPath: String
    /// Full hostname; empty — mc.<domain>
    public var craftyHostname: String
    // AdGuard Home
    public var adguardPath: String
    /// Full hostname; empty — dns.<domain>
    public var adguardHostname: String
    public var piholePath: String
    /// Full hostname; empty — dns.<domain>
    public var piholeHostname: String
    /// Where Pi-hole forwards what it does not block
    public var piholeUpstreams: String
    /// Publish plain DNS on every interface instead of the loopback
    public var piholeServesNetwork: Bool
    // Authelia — single sign-on in front of the admin panels.
    public var autheliaPath: String
    /// Full hostname; empty — auth.<domain>
    public var autheliaHostname: String
    /// Which services SSO stands in front of
    public var autheliaProtectedServices: Set<ServiceID>
    public var homepagePath: String
    /// Full hostname; empty — start.<domain>
    public var homepageHostname: String
    // Headscale
    public var headscalePath: String
    /// Full hostname; empty — mesh.<domain>
    public var headscaleHostname: String
    /// MagicDNS suffix for the nodes; empty — ts.<domain>
    public var headscaleBaseDomain: String
    /// Where the server's own mesh node keeps its state
    public var tailscaleNodePath: String
    public var tailscaleNodeName: String
    public var tailscaleLoginServer: String
    // Cloudflare Tunnel
    public var cloudflaredPath: String
    // Forgejo
    public var forgejoPath: String
    /// Full hostname; empty — git.<domain>
    public var forgejoHostname: String
    public var forgejoSSHPort: Int
    // GitLab CE
    public var gitlabPath: String
    /// Full hostname; empty — gitlab.<domain>
    public var gitlabHostname: String
    public var gitlabSSHPort: Int
    public var vpnHostname: String
    /// Where VPN client configurations are handed out
    public var vpnClientAccess: VPNClientAccess
    public var wireguardVPNPath: String
    /// Public UDP port VPN clients connect to
    public var wireguardVPNPort: Int
    public var amneziaWGPath: String
    /// Public UDP port AmneziaWG clients connect to
    public var amneziaWGPort: Int
    public var shadowsocksPath: String
    /// Public TCP+UDP port clients connect to
    public var shadowsocksPort: Int
    public var xrayRealityPath: String
    public var xrayRealityPort: Int
    public var xrayRealitySNI: String
    public var openVPNPath: String
    /// Public UDP port OpenVPN clients connect to
    public var openVPNPort: Int
    public var ollamaPath: String
    public var ollamaUsesGPU: Bool
    public var ollamaInstallsGPUDriver: Bool
    public var openWebUIPath: String
    /// Full hostname; empty — chat.<domain>
    public var openWebUIHostname: String
    /// Open registration
    public var openWebUIAllowSignups: Bool
    /// Where the gateway's compose file and its `config.yaml` live
    public var liteLLMPath: String
    /// Full hostname; empty — llm.<domain>
    public var liteLLMHostname: String
    public var anythingLLMPath: String
    /// Full hostname; empty — docs.<domain>
    public var anythingLLMHostname: String
    /// Where the vector store keeps its segments
    public var qdrantPath: String
    public var searxngPath: String
    public var openclawPath: String
    /// Full hostname; empty — agent.<domain>
    public var openclawHostname: String
    public var modelBackend: ModelBackend
    // The automation shelf.
    public var n8nPath: String
    /// Full hostname; empty — flows.<domain>
    public var n8nHostname: String
    // The smart-home shelf.
    public var homeAssistantPath: String
    /// Full hostname; empty — home.<domain>
    public var homeAssistantHostname: String
    /// Set when the user confirms this machine is at home
    public var machineAtHome: Bool
    /// A Zigbee or Z-Wave stick's path; empty — none
    public var homeAssistantUSBDevice: String
    public var mosquittoPath: String
    public var zigbee2MQTTPath: String
    /// Full hostname; empty — zigbee.<domain>
    public var zigbee2MQTTHostname: String
    /// The admin username, default "admin"
    public var adminUsername: String
    public var crowdsecEnabled: Bool
    // Backups
    /// Parent of the per-service backup directories
    public var backupRoot: String
    public var backupRetention: Int

    public init(
        mailcowPath: String = "/opt/mailcow-dockerized",
        mailcowBackupDir: String = "/opt/backups/mailcow",
        eraseMailOnDomainChange: Bool = false,
        mailuPath: String = "/opt/mailu",
        mailuSubnet: String = "10.254.29.0/24",
        dockerMailserverPath: String = "/opt/docker-mailserver",
        vaultwardenContainer: String = "vaultwarden",
        vaultwardenDataPath: String = "/opt/vaultwarden/data",
        vaultwardenBackupDir: String = "/opt/backups/vaultwarden",
        vaultwardenHostname: String = "",
        vaultwardenAllowSignups: Bool = false,
        psonoPath: String = "/opt/psono",
        psonoHostname: String = "",
        passboltPath: String = "/opt/passbolt",
        passboltHostname: String = "",
        nextcloudPath: String = "/opt/nextcloud",
        nextcloudHostname: String = "",
        nextcloudAdminUser: String = "admin",
        seafilePath: String = "/opt/seafile",
        seafileHostname: String = "",
        immichPath: String = "/opt/immich",
        immichHostname: String = "",
        photoprismPath: String = "/opt/photoprism",
        photoprismHostname: String = "",
        jellyfinPath: String = "/opt/jellyfin",
        jellyfinHostname: String = "",
        jellyfinMediaPath: String = "/srv/media",
        minecraftJavaPath: String = "/opt/minecraft-java",
        minecraftJavaVersion: String = "",
        minecraftJavaFlavour: String = "PAPER",
        minecraftJavaMemoryMB: Int = 2048,
        minecraftJavaPort: Int = 25565,
        minecraftJavaAcceptsEULA: Bool = false,
        minecraftJavaWhitelist: String = "",
        minecraftJavaOperators: String = "",
        minecraftJavaMods: String = "",
        minecraftBedrockPath: String = "/opt/minecraft-bedrock",
        minecraftBedrockVersion: String = "",
        minecraftBedrockPort: Int = 19132,
        minecraftBedrockAcceptsEULA: Bool = false,
        craftyPath: String = "/opt/crafty",
        craftyHostname: String = "",
        adguardPath: String = "/opt/adguardhome",
        adguardHostname: String = "",
        piholePath: String = "/opt/pihole",
        piholeHostname: String = "",
        piholeUpstreams: String = "1.1.1.1;1.0.0.1",
        piholeServesNetwork: Bool = false,
        autheliaPath: String = "/opt/authelia",
        autheliaHostname: String = "",
        autheliaProtectedServices: Set<ServiceID> = AutheliaService.defaultProtected,
        homepagePath: String = "/opt/homepage",
        homepageHostname: String = "",
        headscalePath: String = "/opt/headscale",
        headscaleHostname: String = "",
        headscaleBaseDomain: String = "",
        tailscaleNodePath: String = "/opt/tailscale",
        tailscaleNodeName: String = "",
        tailscaleLoginServer: String = "",
        cloudflaredPath: String = "/opt/cloudflared",
        forgejoPath: String = "/opt/forgejo",
        forgejoHostname: String = "",
        forgejoSSHPort: Int = 2222,
        gitlabPath: String = "/opt/gitlab-ce",
        gitlabHostname: String = "",
        // 2222 is Forgejo's; both forges may be selected together.
        gitlabSSHPort: Int = 2223,
        vpnHostname: String = "",
        vpnClientAccess: VPNClientAccess = .both,
        wireguardVPNPath: String = "/opt/wgvpn",
        wireguardVPNPort: Int = 51820,
        amneziaWGPath: String = "/opt/awgvpn",
        amneziaWGPort: Int = 51822,
        shadowsocksPath: String = "/opt/shadowsocks",
        shadowsocksPort: Int = 8388,
        xrayRealityPath: String = "/opt/xray",
        xrayRealityPort: Int = 8443,
        xrayRealitySNI: String = "www.apple.com",
        openVPNPath: String = "/opt/openvpn",
        openVPNPort: Int = 1194,
        ollamaPath: String = "/opt/ollama",
        ollamaUsesGPU: Bool = false,
        ollamaInstallsGPUDriver: Bool = false,
        openWebUIPath: String = "/opt/open-webui",
        openWebUIHostname: String = "",
        openWebUIAllowSignups: Bool = false,
        liteLLMPath: String = "/opt/litellm",
        liteLLMHostname: String = "",
        anythingLLMPath: String = "/opt/anythingllm",
        anythingLLMHostname: String = "",
        qdrantPath: String = "/opt/qdrant",
        searxngPath: String = "/opt/searxng",
        openclawPath: String = "/opt/openclaw",
        openclawHostname: String = "",
        modelBackend: ModelBackend = .here,
        n8nPath: String = "/opt/n8n",
        n8nHostname: String = "",
        homeAssistantPath: String = "/opt/home-assistant",
        homeAssistantHostname: String = "",
        machineAtHome: Bool = false,
        homeAssistantUSBDevice: String = "",
        mosquittoPath: String = "/opt/mosquitto",
        zigbee2MQTTPath: String = "/opt/zigbee2mqtt",
        zigbee2MQTTHostname: String = "",
        adminUsername: String = "admin",
        crowdsecEnabled: Bool = true,
        backupRoot: String = "/opt/backups",
        backupRetention: Int = 7
    ) {
        self.mailcowPath = mailcowPath
        self.mailcowBackupDir = mailcowBackupDir
        self.eraseMailOnDomainChange = eraseMailOnDomainChange
        self.mailuPath = mailuPath
        self.mailuSubnet = mailuSubnet
        self.dockerMailserverPath = dockerMailserverPath
        self.vaultwardenContainer = vaultwardenContainer
        self.vaultwardenDataPath = vaultwardenDataPath
        self.vaultwardenBackupDir = vaultwardenBackupDir
        self.vaultwardenHostname = vaultwardenHostname
        self.vaultwardenAllowSignups = vaultwardenAllowSignups
        self.psonoPath = psonoPath
        self.psonoHostname = psonoHostname
        self.passboltPath = passboltPath
        self.passboltHostname = passboltHostname
        self.nextcloudPath = nextcloudPath
        self.nextcloudHostname = nextcloudHostname
        self.nextcloudAdminUser = nextcloudAdminUser
        self.seafilePath = seafilePath
        self.seafileHostname = seafileHostname
        self.immichPath = immichPath
        self.immichHostname = immichHostname
        self.photoprismPath = photoprismPath
        self.photoprismHostname = photoprismHostname
        self.jellyfinPath = jellyfinPath
        self.jellyfinHostname = jellyfinHostname
        self.jellyfinMediaPath = jellyfinMediaPath
        self.minecraftJavaPath = minecraftJavaPath
        self.minecraftJavaVersion = minecraftJavaVersion
        self.minecraftJavaFlavour = minecraftJavaFlavour
        self.minecraftJavaMemoryMB = minecraftJavaMemoryMB
        self.minecraftJavaPort = minecraftJavaPort
        self.minecraftJavaAcceptsEULA = minecraftJavaAcceptsEULA
        self.minecraftJavaWhitelist = minecraftJavaWhitelist
        self.minecraftJavaOperators = minecraftJavaOperators
        self.minecraftJavaMods = minecraftJavaMods
        self.minecraftBedrockPath = minecraftBedrockPath
        self.minecraftBedrockVersion = minecraftBedrockVersion
        self.minecraftBedrockPort = minecraftBedrockPort
        self.minecraftBedrockAcceptsEULA = minecraftBedrockAcceptsEULA
        self.craftyPath = craftyPath
        self.craftyHostname = craftyHostname
        self.adguardPath = adguardPath
        self.adguardHostname = adguardHostname
        self.piholePath = piholePath
        self.piholeHostname = piholeHostname
        self.piholeUpstreams = piholeUpstreams
        self.piholeServesNetwork = piholeServesNetwork
        self.autheliaPath = autheliaPath
        self.autheliaHostname = autheliaHostname
        self.autheliaProtectedServices = autheliaProtectedServices
        self.homepagePath = homepagePath
        self.homepageHostname = homepageHostname
        self.headscalePath = headscalePath
        self.headscaleHostname = headscaleHostname
        self.headscaleBaseDomain = headscaleBaseDomain
        self.tailscaleNodePath = tailscaleNodePath
        self.tailscaleNodeName = tailscaleNodeName
        self.tailscaleLoginServer = tailscaleLoginServer
        self.cloudflaredPath = cloudflaredPath
        self.forgejoPath = forgejoPath
        self.forgejoHostname = forgejoHostname
        self.forgejoSSHPort = forgejoSSHPort
        self.gitlabPath = gitlabPath
        self.gitlabHostname = gitlabHostname
        self.gitlabSSHPort = gitlabSSHPort
        self.vpnHostname = vpnHostname
        self.vpnClientAccess = vpnClientAccess
        self.wireguardVPNPath = wireguardVPNPath
        self.wireguardVPNPort = wireguardVPNPort
        self.amneziaWGPath = amneziaWGPath
        self.amneziaWGPort = amneziaWGPort
        self.shadowsocksPath = shadowsocksPath
        self.shadowsocksPort = shadowsocksPort
        self.xrayRealityPath = xrayRealityPath
        self.xrayRealityPort = xrayRealityPort
        self.xrayRealitySNI = xrayRealitySNI
        self.openVPNPath = openVPNPath
        self.openVPNPort = openVPNPort
        self.ollamaPath = ollamaPath
        self.ollamaUsesGPU = ollamaUsesGPU
        self.ollamaInstallsGPUDriver = ollamaInstallsGPUDriver
        self.openWebUIPath = openWebUIPath
        self.openWebUIHostname = openWebUIHostname
        self.openWebUIAllowSignups = openWebUIAllowSignups
        self.liteLLMPath = liteLLMPath
        self.liteLLMHostname = liteLLMHostname
        self.anythingLLMPath = anythingLLMPath
        self.anythingLLMHostname = anythingLLMHostname
        self.qdrantPath = qdrantPath
        self.searxngPath = searxngPath
        self.openclawPath = openclawPath
        self.openclawHostname = openclawHostname
        self.modelBackend = modelBackend
        self.n8nPath = n8nPath
        self.n8nHostname = n8nHostname
        self.homeAssistantPath = homeAssistantPath
        self.homeAssistantHostname = homeAssistantHostname
        self.machineAtHome = machineAtHome
        self.homeAssistantUSBDevice = homeAssistantUSBDevice
        self.mosquittoPath = mosquittoPath
        self.zigbee2MQTTPath = zigbee2MQTTPath
        self.zigbee2MQTTHostname = zigbee2MQTTHostname
        self.adminUsername = adminUsername
        self.crowdsecEnabled = crowdsecEnabled
        self.backupRoot = backupRoot
        self.backupRetention = backupRetention
    }

    public init(from decoder: Decoder) throws {
        self.init()
        try decodeMail(decoder)
        try decodeFiles(decoder)
        try decodeGames(decoder)
        try decodeNetwork(decoder)
        try decodeForgesAndVPN(decoder)
        try decodeAIAndHost(decoder)
    }

    private mutating func decodeMail(_ decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mailcowPath = try container.decoded(.mailcowPath, or: mailcowPath)
        mailcowBackupDir = try container.decoded(.mailcowBackupDir, or: mailcowBackupDir)
        eraseMailOnDomainChange = try container.decoded(.eraseMailOnDomainChange, or: eraseMailOnDomainChange)
        mailuPath = try container.decoded(.mailuPath, or: mailuPath)
        mailuSubnet = try container.decoded(.mailuSubnet, or: mailuSubnet)
        dockerMailserverPath = try container.decoded(.dockerMailserverPath, or: dockerMailserverPath)
        vaultwardenContainer = try container.decoded(.vaultwardenContainer, or: vaultwardenContainer)
        vaultwardenDataPath = try container.decoded(.vaultwardenDataPath, or: vaultwardenDataPath)
        vaultwardenBackupDir = try container.decoded(.vaultwardenBackupDir, or: vaultwardenBackupDir)
        vaultwardenHostname = try container.decoded(.vaultwardenHostname, or: vaultwardenHostname)
        vaultwardenAllowSignups = try container.decoded(.vaultwardenAllowSignups, or: vaultwardenAllowSignups)
        psonoPath = try container.decoded(.psonoPath, or: psonoPath)
        psonoHostname = try container.decoded(.psonoHostname, or: psonoHostname)
        passboltPath = try container.decoded(.passboltPath, or: passboltPath)
        passboltHostname = try container.decoded(.passboltHostname, or: passboltHostname)
        nextcloudPath = try container.decoded(.nextcloudPath, or: nextcloudPath)
        nextcloudHostname = try container.decoded(.nextcloudHostname, or: nextcloudHostname)
    }

    private mutating func decodeFiles(_ decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nextcloudAdminUser = try container.decoded(.nextcloudAdminUser, or: nextcloudAdminUser)
        seafilePath = try container.decoded(.seafilePath, or: seafilePath)
        seafileHostname = try container.decoded(.seafileHostname, or: seafileHostname)
        immichPath = try container.decoded(.immichPath, or: immichPath)
        immichHostname = try container.decoded(.immichHostname, or: immichHostname)
        photoprismPath = try container.decoded(.photoprismPath, or: photoprismPath)
        photoprismHostname = try container.decoded(.photoprismHostname, or: photoprismHostname)
        jellyfinPath = try container.decoded(.jellyfinPath, or: jellyfinPath)
        jellyfinHostname = try container.decoded(.jellyfinHostname, or: jellyfinHostname)
        jellyfinMediaPath = try container.decoded(.jellyfinMediaPath, or: jellyfinMediaPath)
        minecraftJavaPath = try container.decoded(.minecraftJavaPath, or: minecraftJavaPath)
        minecraftJavaVersion = try container.decoded(.minecraftJavaVersion, or: minecraftJavaVersion)
        minecraftJavaFlavour = try container.decoded(.minecraftJavaFlavour, or: minecraftJavaFlavour)
        minecraftJavaMemoryMB = try container.decoded(.minecraftJavaMemoryMB, or: minecraftJavaMemoryMB)
        minecraftJavaPort = try container.decoded(.minecraftJavaPort, or: minecraftJavaPort)
        minecraftJavaAcceptsEULA = try container.decoded(.minecraftJavaAcceptsEULA, or: minecraftJavaAcceptsEULA)
        minecraftJavaWhitelist = try container.decoded(.minecraftJavaWhitelist, or: minecraftJavaWhitelist)
    }

    private mutating func decodeGames(_ decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minecraftJavaOperators = try container.decoded(.minecraftJavaOperators, or: minecraftJavaOperators)
        minecraftJavaMods = try container.decoded(.minecraftJavaMods, or: minecraftJavaMods)
        minecraftBedrockPath = try container.decoded(.minecraftBedrockPath, or: minecraftBedrockPath)
        minecraftBedrockVersion = try container.decoded(.minecraftBedrockVersion, or: minecraftBedrockVersion)
        minecraftBedrockPort = try container.decoded(.minecraftBedrockPort, or: minecraftBedrockPort)
        minecraftBedrockAcceptsEULA = try container.decoded(.minecraftBedrockAcceptsEULA, or: minecraftBedrockAcceptsEULA)
        craftyPath = try container.decoded(.craftyPath, or: craftyPath)
        craftyHostname = try container.decoded(.craftyHostname, or: craftyHostname)
        adguardPath = try container.decoded(.adguardPath, or: adguardPath)
        adguardHostname = try container.decoded(.adguardHostname, or: adguardHostname)
        piholePath = try container.decoded(.piholePath, or: piholePath)
        piholeHostname = try container.decoded(.piholeHostname, or: piholeHostname)
        piholeUpstreams = try container.decoded(.piholeUpstreams, or: piholeUpstreams)
        piholeServesNetwork = try container.decoded(.piholeServesNetwork, or: piholeServesNetwork)
        autheliaPath = try container.decoded(.autheliaPath, or: autheliaPath)
        autheliaHostname = try container.decoded(.autheliaHostname, or: autheliaHostname)
        autheliaProtectedServices = try container.decoded(.autheliaProtectedServices, or: autheliaProtectedServices)
    }

    private mutating func decodeNetwork(_ decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        homepagePath = try container.decoded(.homepagePath, or: homepagePath)
        homepageHostname = try container.decoded(.homepageHostname, or: homepageHostname)
        headscalePath = try container.decoded(.headscalePath, or: headscalePath)
        headscaleHostname = try container.decoded(.headscaleHostname, or: headscaleHostname)
        headscaleBaseDomain = try container.decoded(.headscaleBaseDomain, or: headscaleBaseDomain)
        tailscaleNodePath = try container.decoded(.tailscaleNodePath, or: tailscaleNodePath)
        tailscaleNodeName = try container.decoded(.tailscaleNodeName, or: tailscaleNodeName)
        tailscaleLoginServer = try container.decoded(.tailscaleLoginServer, or: tailscaleLoginServer)
        cloudflaredPath = try container.decoded(.cloudflaredPath, or: cloudflaredPath)
        forgejoPath = try container.decoded(.forgejoPath, or: forgejoPath)
        forgejoHostname = try container.decoded(.forgejoHostname, or: forgejoHostname)
        forgejoSSHPort = try container.decoded(.forgejoSSHPort, or: forgejoSSHPort)
        gitlabPath = try container.decoded(.gitlabPath, or: gitlabPath)
        gitlabHostname = try container.decoded(.gitlabHostname, or: gitlabHostname)
        gitlabSSHPort = try container.decoded(.gitlabSSHPort, or: gitlabSSHPort)
        vpnHostname = try container.decoded(.vpnHostname, or: vpnHostname)
        vpnClientAccess = try container.decoded(.vpnClientAccess, or: vpnClientAccess)
    }

    private mutating func decodeForgesAndVPN(_ decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wireguardVPNPath = try container.decoded(.wireguardVPNPath, or: wireguardVPNPath)
        wireguardVPNPort = try container.decoded(.wireguardVPNPort, or: wireguardVPNPort)
        amneziaWGPath = try container.decoded(.amneziaWGPath, or: amneziaWGPath)
        amneziaWGPort = try container.decoded(.amneziaWGPort, or: amneziaWGPort)
        shadowsocksPath = try container.decoded(.shadowsocksPath, or: shadowsocksPath)
        shadowsocksPort = try container.decoded(.shadowsocksPort, or: shadowsocksPort)
        xrayRealityPath = try container.decoded(.xrayRealityPath, or: xrayRealityPath)
        xrayRealityPort = try container.decoded(.xrayRealityPort, or: xrayRealityPort)
        xrayRealitySNI = try container.decoded(.xrayRealitySNI, or: xrayRealitySNI)
        openVPNPath = try container.decoded(.openVPNPath, or: openVPNPath)
        openVPNPort = try container.decoded(.openVPNPort, or: openVPNPort)
        ollamaPath = try container.decoded(.ollamaPath, or: ollamaPath)
        ollamaUsesGPU = try container.decoded(.ollamaUsesGPU, or: ollamaUsesGPU)
        ollamaInstallsGPUDriver = try container.decoded(.ollamaInstallsGPUDriver, or: ollamaInstallsGPUDriver)
        openWebUIPath = try container.decoded(.openWebUIPath, or: openWebUIPath)
        openWebUIHostname = try container.decoded(.openWebUIHostname, or: openWebUIHostname)
        openWebUIAllowSignups = try container.decoded(.openWebUIAllowSignups, or: openWebUIAllowSignups)
    }

    private mutating func decodeAIAndHost(_ decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        liteLLMPath = try container.decoded(.liteLLMPath, or: liteLLMPath)
        liteLLMHostname = try container.decoded(.liteLLMHostname, or: liteLLMHostname)
        anythingLLMPath = try container.decoded(.anythingLLMPath, or: anythingLLMPath)
        anythingLLMHostname = try container.decoded(.anythingLLMHostname, or: anythingLLMHostname)
        qdrantPath = try container.decoded(.qdrantPath, or: qdrantPath)
        searxngPath = try container.decoded(.searxngPath, or: searxngPath)
        openclawPath = try container.decoded(.openclawPath, or: openclawPath)
        openclawHostname = try container.decoded(.openclawHostname, or: openclawHostname)
        modelBackend = try container.decoded(.modelBackend, or: modelBackend)
        n8nPath = try container.decoded(.n8nPath, or: n8nPath)
        n8nHostname = try container.decoded(.n8nHostname, or: n8nHostname)
        homeAssistantPath = try container.decoded(.homeAssistantPath, or: homeAssistantPath)
        homeAssistantHostname = try container.decoded(.homeAssistantHostname, or: homeAssistantHostname)
        machineAtHome = try container.decoded(.machineAtHome, or: machineAtHome)
        homeAssistantUSBDevice = try container.decoded(.homeAssistantUSBDevice, or: homeAssistantUSBDevice)
        mosquittoPath = try container.decoded(.mosquittoPath, or: mosquittoPath)
        zigbee2MQTTPath = try container.decoded(.zigbee2MQTTPath, or: zigbee2MQTTPath)
        zigbee2MQTTHostname = try container.decoded(.zigbee2MQTTHostname, or: zigbee2MQTTHostname)
        adminUsername = try container.decoded(.adminUsername, or: adminUsername)
        crowdsecEnabled = try container.decoded(.crowdsecEnabled, or: crowdsecEnabled)
        backupRoot = try container.decoded(.backupRoot, or: backupRoot)
        backupRetention = try container.decoded(.backupRetention, or: backupRetention)
    }
}

private extension KeyedDecodingContainer {
    func decoded<T: Decodable>(_ key: Key, or fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}
