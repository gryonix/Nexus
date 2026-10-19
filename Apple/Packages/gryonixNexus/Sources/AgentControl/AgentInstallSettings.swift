import ServiceCatalog

public enum AgentInstallSettings {
    /// The whole deployment's knobs, ready to hand to `AgentInstallContext`
    public static func map(from settings: ServiceSettings) -> [String: String] {
        [mail(settings), passwords(settings), media(settings), ai(settings),
         games(settings), git(settings), network(settings), vpn(settings), security(settings)]
            .reduce(into: [:]) { $0.merge($1) { _, new in new } }
    }

    private static func mail(_ settings: ServiceSettings) -> [String: String] {
        var out: [String: String] = [:]
        out["mailcow_path"] = settings.mailcowPath
        out["mailu_path"] = settings.mailuPath
        out["mailu_subnet"] = settings.mailuSubnet
        out["docker_mailserver_path"] = settings.dockerMailserverPath
        return out
    }

    private static func passwords(_ settings: ServiceSettings) -> [String: String] {
        var out: [String: String] = [:]
        out["vaultwarden_hostname"] = settings.vaultwardenHostname
        out["vaultwarden_container"] = settings.vaultwardenContainer
        out["vaultwarden_data_path"] = settings.vaultwardenDataPath
        out["vaultwarden_allow_signups"] = settings.vaultwardenAllowSignups ? "true" : "false"
        out["psono_hostname"] = settings.psonoHostname
        out["psono_path"] = settings.psonoPath
        out["passbolt_hostname"] = settings.passboltHostname
        out["passbolt_path"] = settings.passboltPath
        return out
    }

    private static func media(_ settings: ServiceSettings) -> [String: String] {
        var out: [String: String] = [:]
        out["nextcloud_hostname"] = settings.nextcloudHostname
        out["nextcloud_path"] = settings.nextcloudPath
        out["seafile_hostname"] = settings.seafileHostname
        out["seafile_path"] = settings.seafilePath
        out["immich_hostname"] = settings.immichHostname
        out["immich_path"] = settings.immichPath
        out["photoprism_hostname"] = settings.photoprismHostname
        out["photoprism_path"] = settings.photoprismPath
        out["jellyfin_hostname"] = settings.jellyfinHostname
        out["jellyfin_path"] = settings.jellyfinPath
        out["jellyfin_media_path"] = settings.jellyfinMediaPath
        out["home_assistant_hostname"] = settings.homeAssistantHostname
        out["home_assistant_path"] = settings.homeAssistantPath
        out["machine_at_home"] = settings.machineAtHome ? "true" : "false"
        return out
    }

    private static func ai(_ settings: ServiceSettings) -> [String: String] {
        var out: [String: String] = [:]
        out["ollama_path"] = settings.ollamaPath
        out["open_webui_path"] = settings.openWebUIPath
        out["open_webui_hostname"] = settings.openWebUIHostname
        out["open_webui_allow_signups"] = settings.openWebUIAllowSignups ? "true" : "false"
        out["litellm_path"] = settings.liteLLMPath
        out["litellm_hostname"] = settings.liteLLMHostname
        out["anythingllm_path"] = settings.anythingLLMPath
        out["anythingllm_hostname"] = settings.anythingLLMHostname
        out["qdrant_path"] = settings.qdrantPath
        out["searxng_path"] = settings.searxngPath
        out["openclaw_path"] = settings.openclawPath
        out["openclaw_hostname"] = settings.openclawHostname
        return out
    }

    private static func games(_ settings: ServiceSettings) -> [String: String] {
        var out: [String: String] = [:]
        out["minecraft_java_path"] = settings.minecraftJavaPath
        out["minecraft_java_version"] = settings.minecraftJavaVersion
        out["minecraft_java_flavour"] = settings.minecraftJavaFlavour
        out["minecraft_java_memory_mb"] = String(settings.minecraftJavaMemoryMB)
        out["minecraft_java_port"] = String(settings.minecraftJavaPort)
        out["minecraft_java_accepts_eula"] = settings.minecraftJavaAcceptsEULA ? "true" : "false"
        out["minecraft_java_whitelist"] = settings.minecraftJavaWhitelist
        out["minecraft_java_operators"] = settings.minecraftJavaOperators
        out["minecraft_java_mods"] = settings.minecraftJavaMods
        out["minecraft_bedrock_path"] = settings.minecraftBedrockPath
        out["minecraft_bedrock_version"] = settings.minecraftBedrockVersion
        out["minecraft_bedrock_port"] = String(settings.minecraftBedrockPort)
        out["minecraft_bedrock_accepts_eula"] = settings.minecraftBedrockAcceptsEULA ? "true" : "false"
        out["crafty_hostname"] = settings.craftyHostname
        out["crafty_path"] = settings.craftyPath
        return out
    }

    private static func git(_ settings: ServiceSettings) -> [String: String] {
        var out: [String: String] = [:]
        out["forgejo_hostname"] = settings.forgejoHostname
        out["forgejo_path"] = settings.forgejoPath
        out["forgejo_ssh_port"] = String(settings.forgejoSSHPort)
        out["gitlab_hostname"] = settings.gitlabHostname
        out["gitlab_path"] = settings.gitlabPath
        out["gitlab_ssh_port"] = String(settings.gitlabSSHPort)
        return out
    }

    private static func network(_ settings: ServiceSettings) -> [String: String] {
        var out: [String: String] = [:]
        out["adguard_hostname"] = settings.adguardHostname
        out["adguard_path"] = settings.adguardPath
        out["authelia_hostname"] = settings.autheliaHostname
        out["authelia_path"] = settings.autheliaPath
        out["authelia_protected_services"] = ServiceRegistry
            .services(settings.autheliaProtectedServices)
            .map(\.id.rawValue)
            .joined(separator: ",")
        out["homepage_hostname"] = settings.homepageHostname
        out["homepage_path"] = settings.homepagePath
        out["pihole_hostname"] = settings.piholeHostname
        out["pihole_path"] = settings.piholePath
        out["pihole_upstreams"] = settings.piholeUpstreams
        out["pihole_serves_network"] = settings.piholeServesNetwork ? "true" : "false"
        out["headscale_base_domain"] = settings.headscaleBaseDomain
        out["headscale_hostname"] = settings.headscaleHostname
        out["headscale_path"] = settings.headscalePath
        out["tailscale_node_path"] = settings.tailscaleNodePath
        out["tailscale_node_name"] = settings.tailscaleNodeName
        out["tailscale_login_server"] = settings.tailscaleLoginServer
        out["cloudflared_path"] = settings.cloudflaredPath
        return out
    }

    private static func vpn(_ settings: ServiceSettings) -> [String: String] {
        var out: [String: String] = [:]
        out["vpn_hostname"] = settings.vpnHostname
        out["vpn_client_access"] = settings.vpnClientAccess.rawValue
        out["wireguard_vpn_port"] = String(settings.wireguardVPNPort)
        out["amnezia_wg_path"] = settings.amneziaWGPath
        out["amnezia_wg_port"] = String(settings.amneziaWGPort)
        out["shadowsocks_path"] = settings.shadowsocksPath
        out["shadowsocks_port"] = String(settings.shadowsocksPort)
        out["xray_reality_path"] = settings.xrayRealityPath
        out["xray_reality_port"] = String(settings.xrayRealityPort)
        out["xray_reality_sni"] = settings.xrayRealitySNI
        out["openvpn_path"] = settings.openVPNPath
        out["openvpn_port"] = String(settings.openVPNPort)
        return out
    }

    private static func security(_ settings: ServiceSettings) -> [String: String] {
        var out: [String: String] = [:]
        out["crowdsec_enabled"] = settings.crowdsecEnabled ? "true" : "false"
        return out
    }

    /// Every key [`map(from:)`] produces, as data
    public static let keys: Set<String> = [
        "mailcow_path", "mailu_path", "mailu_subnet", "docker_mailserver_path",
        "vaultwarden_hostname", "vaultwarden_container", "vaultwarden_data_path",
        "vaultwarden_allow_signups",
        "psono_hostname", "psono_path", "passbolt_hostname", "passbolt_path",
        "nextcloud_hostname", "nextcloud_path", "seafile_hostname", "seafile_path",
        "immich_hostname", "immich_path", "photoprism_hostname", "photoprism_path",
        "jellyfin_hostname", "jellyfin_path", "jellyfin_media_path",
        "home_assistant_hostname", "home_assistant_path", "machine_at_home",
        "anythingllm_path", "anythingllm_hostname", "qdrant_path", "searxng_path", "openclaw_path", "openclaw_hostname",
        "minecraft_java_path", "minecraft_java_version", "minecraft_java_flavour",
        "minecraft_java_memory_mb", "minecraft_java_port", "minecraft_java_accepts_eula",
        "minecraft_java_whitelist", "minecraft_java_operators", "minecraft_java_mods",
        "minecraft_bedrock_path", "minecraft_bedrock_version", "minecraft_bedrock_port",
        "minecraft_bedrock_accepts_eula",
        "crafty_hostname", "crafty_path",
        "ollama_path", "open_webui_path", "open_webui_hostname", "open_webui_allow_signups",
        "litellm_path", "litellm_hostname",
        "forgejo_hostname", "forgejo_path", "forgejo_ssh_port",
        "gitlab_hostname", "gitlab_path", "gitlab_ssh_port",
        "adguard_hostname", "adguard_path",
        "pihole_hostname", "pihole_path", "pihole_upstreams", "pihole_serves_network",
        "homepage_hostname", "homepage_path",
        "authelia_hostname", "authelia_path", "authelia_protected_services",
        "headscale_base_domain", "headscale_hostname", "headscale_path",
        "tailscale_node_path", "tailscale_node_name", "tailscale_login_server",
        "cloudflared_path",
        "vpn_hostname", "vpn_client_access", "wireguard_vpn_port",
        "amnezia_wg_path", "amnezia_wg_port",
        "shadowsocks_path", "shadowsocks_port",
        "xray_reality_path", "xray_reality_port", "xray_reality_sni",
        "openvpn_path", "openvpn_port",
        "crowdsec_enabled"
    ]

    public static let cloudflaredTokenKey = "cloudflared_token"

    public static let tailscaleAuthKeyKey = "tailscale_auth_key"

    public static let vpnProtocolsKey = "vpn_protocols"

    /// A one-time request for a new Reality key
    public static let xrayRealityNewKeyKey = "xray_reality_new_key"

    public static func vpnProtocolList(adding service: ServiceID,
                                       installed: Set<ServiceID>) -> String? {
        guard ServiceID.vpnProtocols.contains(service) || service == .vpnPanel else { return nil }
        var ids = installed.filter { ServiceID.vpnProtocols.contains($0) }
        if ServiceID.vpnProtocols.contains(service) { ids.insert(service) }
        let ordered = ServiceRegistry.all.map(\.id).filter { ids.contains($0) }
        return ordered.isEmpty ? nil : ordered.map(\.rawValue).joined(separator: ",")
    }
}
