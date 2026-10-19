package com.skaymer.gryonixnexus.catalog

import kotlinx.serialization.Serializable

@Serializable
data class ServiceContext(
    /** Mail/base domain, e.g */
    val domain: String,
    /** Further domains this server also answers on */
    val additionalDomains: List<String> = emptyList(),
    /** Dashboard's ssh login on the server; the sudoers subject */
    val sshUser: String,
    val settings: ServiceSettings = ServiceSettings(),
    val language: AppLanguage = AppLanguage.EN,
    /** Every service being installed on this host */
    val installedServices: Set<ServiceID> = emptySet(),
    /** Caddy signs its own certificate here */
    val usesInternalTLS: Boolean = false,
) {
    fun mirroredHostnames(hostname: String): List<String> {
        if (!hostname.endsWith(".$domain")) return emptyList()
        val prefix = hostname.dropLast(domain.length + 1)
        return additionalDomains.map { "$prefix.$it" }
    }

    fun servedHostnames(hostname: String): List<String> =
        listOf(hostname) + mirroredHostnames(hostname)

    /** Where a service's backups live */
    fun backupDirectory(id: ServiceID): String = when (id) {
        ServiceID.MAILCOW -> settings.mailcowBackupDir
        ServiceID.VAULTWARDEN -> settings.vaultwardenBackupDir
        else -> "${settings.backupRoot}/${id.rawValue}"
    }
}

/** Per-service knobs, all with working defaults */
@Serializable
data class ServiceSettings(
    // Mailcow
    val mailcowPath: String = "/opt/mailcow-dockerized",
    val mailcowBackupDir: String = "/opt/backups/mailcow",
    val eraseMailOnDomainChange: Boolean = false,

    val mailuPath: String = "/opt/mailu",
    /** Docker network the Mailu stack runs on */
    val mailuSubnet: String = "10.254.29.0/24",

    val dockerMailserverPath: String = "/opt/docker-mailserver",

    // Vaultwarden
    val vaultwardenContainer: String = "vaultwarden",
    val vaultwardenDataPath: String = "/opt/vaultwarden/data",
    val vaultwardenBackupDir: String = "/opt/backups/vaultwarden",
    /** Full web UI hostname; empty — vault.<domain> */
    val vaultwardenHostname: String = "",
    /** Open registration; off — access only by invitation from /admin */
    val vaultwardenAllowSignups: Boolean = false,

    val psonoPath: String = "/opt/psono",
    /** Full hostname; empty — psono.<domain> */
    val psonoHostname: String = "",

    // Passbolt — the third engine on the passwords shelf, GPG-based.
    val passboltPath: String = "/opt/passbolt",
    /** Full hostname; empty — passbolt.<domain> */
    val passboltHostname: String = "",

    // Nextcloud
    val nextcloudPath: String = "/opt/nextcloud",
    /** Full hostname; empty — cloud.<domain> */
    val nextcloudHostname: String = "",
    /** Admin login, created on the container's first run */
    val nextcloudAdminUser: String = "admin",

    val seafilePath: String = "/opt/seafile",
    /** Full hostname; empty — files.<domain> */
    val seafileHostname: String = "",

    // Immich
    val immichPath: String = "/opt/immich",
    /** Full hostname; empty — photos.<domain> */
    val immichHostname: String = "",

    // PhotoPrism — the second engine on the photos shelf.
    val photoprismPath: String = "/opt/photoprism",
    /** Full hostname; empty — photoprism.<domain> */
    val photoprismHostname: String = "",

    // Jellyfin
    val jellyfinPath: String = "/opt/jellyfin",
    /** Full hostname; empty — media.<domain> */
    val jellyfinHostname: String = "",
    /** Where the media library lives */
    val jellyfinMediaPath: String = "/srv/media",

    val minecraftJavaPath: String = "/opt/minecraft-java",
    /** Game version, e.g */
    val minecraftJavaVersion: String = "",
    /** Server flavour: VANILLA, PAPER, FABRIC, FORGE */
    val minecraftJavaFlavour: String = "PAPER",
    /** Heap for the JVM */
    val minecraftJavaMemoryMB: Int = 2048,
    val minecraftJavaPort: Int = 25565,
    /** Mojang's EULA, which the server refuses to start without */
    val minecraftJavaAcceptsEULA: Boolean = false,
    /** Player names allowed on, comma separated */
    val minecraftJavaWhitelist: String = "",
    /** Player names with operator rights, comma separated */
    val minecraftJavaOperators: String = "",
    val minecraftJavaMods: String = "",

    // Minecraft, Bedrock edition — phones, consoles and the Windows app.
    val minecraftBedrockPath: String = "/opt/minecraft-bedrock",
    val minecraftBedrockVersion: String = "",
    val minecraftBedrockPort: Int = 19132,
    val minecraftBedrockAcceptsEULA: Boolean = false,

    // Crafty Controller — the panel in front of the game servers.
    val craftyPath: String = "/opt/crafty",
    /** Full hostname; empty — mc.<domain> */
    val craftyHostname: String = "",

    val ollamaPath: String = "/opt/ollama",
    val ollamaUsesGPU: Boolean = false,
    val ollamaInstallsGPUDriver: Boolean = false,
    val openWebUIPath: String = "/opt/open-webui",
    /** Full hostname; empty — chat.<domain> */
    val openWebUIHostname: String = "",
    /** Open registration */
    val openWebUIAllowSignups: Boolean = false,
    val liteLLMPath: String = "/opt/litellm",
    /** Full hostname; empty — llm.<domain> */
    val liteLLMHostname: String = "",
    val modelBackend: ModelBackend = ModelBackend.HERE,
    // The automation shelf.
    val n8nPath: String = "/opt/n8n",
    /** Full hostname; empty — flows.<domain> */
    val n8nHostname: String = "",
    // The smart-home shelf.
    val homeAssistantPath: String = "/opt/home-assistant",
    /** Full hostname; empty — home.<domain> */
    val homeAssistantHostname: String = "",
    /** Set when the user confirms this machine is at home */
    val machineAtHome: Boolean = false,
    /** A Zigbee or Z-Wave stick's path; empty — none */
    val homeAssistantUSBDevice: String = "",
    val mosquittoPath: String = "/opt/mosquitto",
    val zigbee2MQTTPath: String = "/opt/zigbee2mqtt",
    /** Full hostname; empty — zigbee.<domain> */
    val zigbee2MQTTHostname: String = "",
    // The retrieval pair.
    val anythingLLMPath: String = "/opt/anythingllm",
    /** Full hostname; empty — docs.<domain> */
    val anythingLLMHostname: String = "",
    /** Where the vector store keeps its segments */
    val qdrantPath: String = "/opt/qdrant",
    val searxngPath: String = "/opt/searxng",
    val openclawPath: String = "/opt/openclaw",
    /** Full hostname; empty — agent.<domain> */
    val openclawHostname: String = "",

    // AdGuard Home
    val adguardPath: String = "/opt/adguardhome",
    /** Full hostname; empty — dns.<domain> */
    val adguardHostname: String = "",

    val piholePath: String = "/opt/pihole",
    /** Full hostname; empty — dns.<domain> */
    val piholeHostname: String = "",
    /** Where Pi-hole forwards what it does not block */
    val piholeUpstreams: String = "1.1.1.1;1.0.0.1",
    /** Publish plain DNS on every interface instead of the loopback */
    val piholeServesNetwork: Boolean = false,

    // Authelia — single sign-on in front of the admin panels.
    val autheliaPath: String = "/opt/authelia",
    /** Full hostname; empty — auth.<domain> */
    val autheliaHostname: String = "",
    /** Which services SSO stands in front of */
    val autheliaProtectedServices: Set<ServiceID> = AutheliaDefaults.PROTECTED,

    val homepagePath: String = "/opt/homepage",
    /** Full hostname; empty — start.<domain> */
    val homepageHostname: String = "",

    // Headscale
    val headscalePath: String = "/opt/headscale",
    /** Full hostname; empty — mesh.<domain> */
    val headscaleHostname: String = "",
    /** MagicDNS suffix for the nodes; empty — ts.<domain> */
    val headscaleBaseDomain: String = "",
    /** Where the server's own mesh node keeps its state */
    val tailscaleNodePath: String = "/opt/tailscale",
    val tailscaleNodeName: String = "",
    val tailscaleLoginServer: String = "",

    // Cloudflare Tunnel
    val cloudflaredPath: String = "/opt/cloudflared",

    // Forgejo
    val forgejoPath: String = "/opt/forgejo",
    /** Full hostname; empty — git.<domain> */
    val forgejoHostname: String = "",
    val forgejoSSHPort: Int = 2222,

    // GitLab CE
    val gitlabPath: String = "/opt/gitlab-ce",
    /** Full hostname; empty — gitlab.<domain> */
    val gitlabHostname: String = "",
    /** Public TCP port of GitLab's built-in SSH server */
    val gitlabSSHPort: Int = 2223,

    val vpnHostname: String = "",
    /** Where VPN client configurations are handed out */
    val vpnClientAccess: VPNClientAccess = VPNClientAccess.BOTH,

    val wireguardVPNPath: String = "/opt/wgvpn",
    /** Public UDP port VPN clients connect to */
    val wireguardVPNPort: Int = 51820,

    val amneziaWGPath: String = "/opt/awgvpn",
    /** Public UDP port AmneziaWG clients connect to */
    val amneziaWGPort: Int = 51822,

    val shadowsocksPath: String = "/opt/shadowsocks",
    /** Public TCP+UDP port clients connect to */
    val shadowsocksPort: Int = 8388,

    // Xray VLESS/Reality — DPI-resistant TLS camouflage, TCP only, not HTTP.
    val xrayRealityPath: String = "/opt/xray",
    val xrayRealityPort: Int = 8443,
    val xrayRealitySNI: String = "www.apple.com",

    // OpenVPN (kylemanna/openvpn) — classic UDP VPN with an EasyRSA PKI.
    val openVPNPath: String = "/opt/openvpn",
    /** Public UDP port OpenVPN clients connect to */
    val openVPNPort: Int = 1194,

    /** The admin username, default "admin" */
    val adminUsername: String = "admin",

    val crowdsecEnabled: Boolean = true,

    // Backups
    /** Parent of the per-service backup directories */
    val backupRoot: String = "/opt/backups",
    val backupRetention: Int = 7
)

/** The SSO default, kept beside the setting that carries it */
object AutheliaDefaults {
    val PROTECTED: Set<ServiceID> = setOf(
        ServiceID.ADGUARD_HOME, ServiceID.PIHOLE, ServiceID.HOMEPAGE,
        ServiceID.CRAFTY_CONTROLLER
    )
}
