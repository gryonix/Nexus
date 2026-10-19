package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.ServiceSettings

object AgentInstallSettings {
    fun map(settings: ServiceSettings): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        val groups = listOf(::mail, ::passwords, ::mediaAndAI, ::games, ::git, ::network, ::vpn, ::security)
        for (group in groups) out.putAll(group(settings))
        return out
    }

    private fun mail(settings: ServiceSettings): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        out["mailcow_path"] = settings.mailcowPath
        out["mailu_path"] = settings.mailuPath
        out["mailu_subnet"] = settings.mailuSubnet
        out["docker_mailserver_path"] = settings.dockerMailserverPath
        return out
    }

    private fun passwords(settings: ServiceSettings): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        out["vaultwarden_hostname"] = settings.vaultwardenHostname
        out["vaultwarden_container"] = settings.vaultwardenContainer
        out["vaultwarden_data_path"] = settings.vaultwardenDataPath
        out["vaultwarden_allow_signups"] = bool(settings.vaultwardenAllowSignups)
        out["psono_hostname"] = settings.psonoHostname
        out["psono_path"] = settings.psonoPath
        out["passbolt_hostname"] = settings.passboltHostname
        out["passbolt_path"] = settings.passboltPath
        return out
    }

    private fun mediaAndAI(settings: ServiceSettings): Map<String, String> {
        val out = LinkedHashMap<String, String>()
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
        out["machine_at_home"] = if (settings.machineAtHome) "true" else "false"
        out["ollama_path"] = settings.ollamaPath
        out["open_webui_path"] = settings.openWebUIPath
        out["open_webui_hostname"] = settings.openWebUIHostname
        out["open_webui_allow_signups"] = bool(settings.openWebUIAllowSignups)
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

    private fun games(settings: ServiceSettings): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        out["minecraft_java_path"] = settings.minecraftJavaPath
        out["minecraft_java_version"] = settings.minecraftJavaVersion
        out["minecraft_java_flavour"] = settings.minecraftJavaFlavour
        out["minecraft_java_memory_mb"] = settings.minecraftJavaMemoryMB.toString()
        out["minecraft_java_port"] = settings.minecraftJavaPort.toString()
        out["minecraft_java_accepts_eula"] = bool(settings.minecraftJavaAcceptsEULA)
        out["minecraft_java_whitelist"] = settings.minecraftJavaWhitelist
        out["minecraft_java_operators"] = settings.minecraftJavaOperators
        out["minecraft_java_mods"] = settings.minecraftJavaMods
        out["minecraft_bedrock_path"] = settings.minecraftBedrockPath
        out["minecraft_bedrock_version"] = settings.minecraftBedrockVersion
        out["minecraft_bedrock_port"] = settings.minecraftBedrockPort.toString()
        out["minecraft_bedrock_accepts_eula"] = bool(settings.minecraftBedrockAcceptsEULA)
        out["crafty_hostname"] = settings.craftyHostname
        out["crafty_path"] = settings.craftyPath
        return out
    }

    private fun git(settings: ServiceSettings): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        out["forgejo_hostname"] = settings.forgejoHostname
        out["forgejo_path"] = settings.forgejoPath
        out["forgejo_ssh_port"] = settings.forgejoSSHPort.toString()
        out["gitlab_hostname"] = settings.gitlabHostname
        out["gitlab_path"] = settings.gitlabPath
        out["gitlab_ssh_port"] = settings.gitlabSSHPort.toString()
        return out
    }

    private fun network(settings: ServiceSettings): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        out["adguard_hostname"] = settings.adguardHostname
        out["adguard_path"] = settings.adguardPath
        out["authelia_hostname"] = settings.autheliaHostname
        out["authelia_path"] = settings.autheliaPath
        out["authelia_protected_services"] = ServiceRegistry
            .services(settings.autheliaProtectedServices)
            .joinToString(",") { it.id.rawValue }
        out["homepage_hostname"] = settings.homepageHostname
        out["homepage_path"] = settings.homepagePath
        out["pihole_hostname"] = settings.piholeHostname
        out["pihole_path"] = settings.piholePath
        out["pihole_upstreams"] = settings.piholeUpstreams
        out["pihole_serves_network"] = bool(settings.piholeServesNetwork)
        out["headscale_base_domain"] = settings.headscaleBaseDomain
        out["headscale_hostname"] = settings.headscaleHostname
        out["headscale_path"] = settings.headscalePath
        out["tailscale_node_path"] = settings.tailscaleNodePath
        out["tailscale_node_name"] = settings.tailscaleNodeName
        out["tailscale_login_server"] = settings.tailscaleLoginServer
        out["cloudflared_path"] = settings.cloudflaredPath
        return out
    }

    private fun vpn(settings: ServiceSettings): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        out["vpn_hostname"] = settings.vpnHostname
        out["vpn_client_access"] = settings.vpnClientAccess.wireValue
        out["wireguard_vpn_port"] = settings.wireguardVPNPort.toString()
        out["amnezia_wg_path"] = settings.amneziaWGPath
        out["amnezia_wg_port"] = settings.amneziaWGPort.toString()
        out["shadowsocks_path"] = settings.shadowsocksPath
        out["shadowsocks_port"] = settings.shadowsocksPort.toString()
        out["xray_reality_path"] = settings.xrayRealityPath
        out["xray_reality_port"] = settings.xrayRealityPort.toString()
        out["xray_reality_sni"] = settings.xrayRealitySNI
        out["openvpn_path"] = settings.openVPNPath
        out["openvpn_port"] = settings.openVPNPort.toString()
        return out
    }

    private fun security(settings: ServiceSettings): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        out["crowdsec_enabled"] = bool(settings.crowdsecEnabled)
        return out
    }

    /** Every key [map] produces, as data */
    val keys: Set<String> = setOf(
        "mailcow_path", "mailu_path", "mailu_subnet", "docker_mailserver_path",
        "vaultwarden_hostname", "vaultwarden_container", "vaultwarden_data_path",
        "vaultwarden_allow_signups",
        "psono_hostname", "psono_path", "passbolt_hostname", "passbolt_path",
        "nextcloud_hostname", "nextcloud_path", "seafile_hostname", "seafile_path",
        "immich_hostname", "immich_path", "photoprism_hostname", "photoprism_path",
        "jellyfin_hostname", "jellyfin_path", "jellyfin_media_path",
        "home_assistant_hostname", "home_assistant_path", "machine_at_home",
        "ollama_path", "open_webui_path", "open_webui_hostname", "open_webui_allow_signups", "litellm_path", "litellm_hostname", "anythingllm_path", "anythingllm_hostname", "qdrant_path", "searxng_path", "openclaw_path", "openclaw_hostname",
        "minecraft_java_path", "minecraft_java_version", "minecraft_java_flavour",
        "minecraft_java_memory_mb", "minecraft_java_port", "minecraft_java_accepts_eula",
        "minecraft_java_whitelist", "minecraft_java_operators", "minecraft_java_mods",
        "minecraft_bedrock_path", "minecraft_bedrock_version", "minecraft_bedrock_port",
        "minecraft_bedrock_accepts_eula",
        "crafty_hostname", "crafty_path",
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
        "crowdsec_enabled",
    )

    const val CLOUDFLARED_TOKEN_KEY = "cloudflared_token"

    const val TAILSCALE_AUTH_KEY_KEY = "tailscale_auth_key"

    const val VPN_PROTOCOLS_KEY = "vpn_protocols"

    /** A one-time request for a new Reality key */
    const val XRAY_REALITY_NEW_KEY_KEY = "xray_reality_new_key"

    fun vpnProtocolList(service: ServiceID, installed: Set<ServiceID>): String? {
        if (service !in ServiceID.VPN_PROTOCOLS && service != ServiceID.VPN_PANEL) return null
        val ids = installed.filterTo(mutableSetOf()) { it in ServiceID.VPN_PROTOCOLS }
        if (service in ServiceID.VPN_PROTOCOLS) ids += service
        val ordered = ServiceRegistry.all.map { it.id }.filter { it in ids }
        return ordered.takeIf { it.isNotEmpty() }?.joinToString(",") { it.rawValue }
    }

    private fun bool(value: Boolean) = if (value) "true" else "false"
}
