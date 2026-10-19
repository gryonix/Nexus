package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.ServiceID

object AgentServiceMapping {
    /** Agent id → app id */
    private val byAgentID: Map<String, ServiceID> = mapOf(
        "mailcow" to ServiceID.MAILCOW,
        "mailu" to ServiceID.MAILU,
        "docker-mailserver" to ServiceID.DOCKER_MAILSERVER,
        "vaultwarden" to ServiceID.VAULTWARDEN,
        "psono" to ServiceID.PSONO,
        "passbolt" to ServiceID.PASSBOLT,
        "nextcloud" to ServiceID.NEXTCLOUD,
        "seafile" to ServiceID.SEAFILE,
        "immich" to ServiceID.IMMICH,
        "forgejo" to ServiceID.FORGEJO,
        "gitlab" to ServiceID.GITLAB,
        "jellyfin" to ServiceID.JELLYFIN,
        "photoprism" to ServiceID.PHOTOPRISM,
        "adguard-home" to ServiceID.ADGUARD_HOME,
        "pihole" to ServiceID.PIHOLE,
        "homepage" to ServiceID.HOMEPAGE,
        "authelia" to ServiceID.AUTHELIA,
        "headscale" to ServiceID.HEADSCALE,
        "tailscale-node" to ServiceID.TAILSCALE_NODE,
        "cloudflared" to ServiceID.CLOUDFLARED,
        "minecraft-java" to ServiceID.MINECRAFT_JAVA,
        "minecraft-bedrock" to ServiceID.MINECRAFT_BEDROCK,
        "crafty-controller" to ServiceID.CRAFTY_CONTROLLER,
        "open-webui" to ServiceID.OPEN_WEB_UI,
        "ollama" to ServiceID.OLLAMA,
        "litellm" to ServiceID.LITE_LLM,
        "n8n" to ServiceID.N8N,
        "home-assistant" to ServiceID.HOME_ASSISTANT,
        "mosquitto" to ServiceID.MOSQUITTO,
        "zigbee2mqtt" to ServiceID.ZIGBEE2MQTT,
        "anythingllm" to ServiceID.ANYTHING_LLM,
        "qdrant" to ServiceID.QDRANT,
        "searxng" to ServiceID.SEARXNG,
        "openclaw" to ServiceID.OPENCLAW,
        // The aggregate: panel plus whatever protocols the host is running.
        "vpn" to ServiceID.VPN_PANEL,
    )

    fun serviceIDs(agentIDs: List<String>): Set<ServiceID> =
        agentIDs.mapNotNull { byAgentID[it] }.toSet()

    fun serviceIDsForServices(services: List<Pair<String, List<String>>>): Set<ServiceID> {
        val result = serviceIDs(services.map { it.first }).toMutableSet()
        for (service in services) {
            if (service.first == "vpn") result += vpnProtocols(service.second)
        }
        return result
    }

    /** Container name → protocol, for the four engines that run one */
    private val protocolContainers: Map<String, ServiceID> = mapOf(
        "awgvpn" to ServiceID.AMNEZIA_WG,
        "openvpn" to ServiceID.OPEN_VPN,
        "shadowsocks" to ServiceID.SHADOWSOCKS,
        "xray" to ServiceID.XRAY_REALITY,
    )

    fun vpnProtocols(runningContainers: List<String>): Set<ServiceID> {
        val found = runningContainers.mapNotNull { protocolContainers[it] }.toMutableSet()
        if (runningContainers.contains("vpnpanel") && found.isEmpty()) {
            found += ServiceID.WIREGUARD_VPN
        }
        return found
    }

    fun serviceID(agentID: String): ServiceID? = byAgentID[agentID]

    fun agentID(service: ServiceID): String? {
        if (service == ServiceID.VPN_PANEL || service in ServiceID.VPN_PROTOCOLS) return "vpn"
        return byAgentID.entries.firstOrNull { it.value == service }?.key
    }

    /** Every agent id this build knows — the table's own inventory */
    val knownAgentIDs: Set<String> get() = byAgentID.keys
}
