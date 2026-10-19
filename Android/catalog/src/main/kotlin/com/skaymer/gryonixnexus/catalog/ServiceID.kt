package com.skaymer.gryonixnexus.catalog

import kotlinx.serialization.Serializable

/** Identifier of a managed self-hosted service */
@Serializable
@JvmInline
value class ServiceID(val rawValue: String) : Comparable<ServiceID> {
    override fun compareTo(other: ServiceID): Int = rawValue.compareTo(other.rawValue)
    override fun toString(): String = rawValue

    companion object {
        val MAILCOW = ServiceID("mailcow")
        val MAILU = ServiceID("mailu")
        val DOCKER_MAILSERVER = ServiceID("docker-mailserver")
        val VAULTWARDEN = ServiceID("vaultwarden")
        val PSONO = ServiceID("psono")
        val PASSBOLT = ServiceID("passbolt")
        val NEXTCLOUD = ServiceID("nextcloud")
        val SEAFILE = ServiceID("seafile")
        val IMMICH = ServiceID("immich")
        val FORGEJO = ServiceID("forgejo")
        val GITLAB = ServiceID("gitlab")
        val JELLYFIN = ServiceID("jellyfin")
        val ADGUARD_HOME = ServiceID("adguard-home")
        val PIHOLE = ServiceID("pihole")
        val HOMEPAGE = ServiceID("homepage")
        val AUTHELIA = ServiceID("authelia")
        val HEADSCALE = ServiceID("headscale")
        val CLOUDFLARED = ServiceID("cloudflared")
        val PHOTOPRISM = ServiceID("photoprism")
        val WIREGUARD_VPN = ServiceID("wireguard-vpn")
        val AMNEZIA_WG = ServiceID("amnezia-wg")
        val SHADOWSOCKS = ServiceID("shadowsocks")
        val XRAY_REALITY = ServiceID("xray-reality")
        val OPEN_VPN = ServiceID("openvpn")

        val VPN_PANEL = ServiceID("vpn-panel")

        /** The server's own membership of the mesh it hosts */
        val TAILSCALE_NODE = ServiceID("tailscale-node")

        val MINECRAFT_JAVA = ServiceID("minecraft-java")
        val MINECRAFT_BEDROCK = ServiceID("minecraft-bedrock")

        val CRAFTY_CONTROLLER = ServiceID("crafty-controller")

        /** The local model engine */
        val OLLAMA = ServiceID("ollama")

        val OPEN_WEB_UI = ServiceID("open-webui")

        val LITE_LLM = ServiceID("litellm")

        /** The automation engine — "when this happens, do that" */
        val N8N = ServiceID("n8n")

        /** The smart-home hub */
        val HOME_ASSISTANT = ServiceID("home-assistant")

        /** The MQTT broker the hub's devices talk over */
        val MOSQUITTO = ServiceID("mosquitto")

        /** Zigbee devices, through a stick on the machine */
        val ZIGBEE2MQTT = ServiceID("zigbee2mqtt")

        /** The hub's own add-ons: never offered, and never installed, alone */
        val SMART_HOME_ADD_ONS = setOf(MOSQUITTO, ZIGBEE2MQTT)

        val ANYTHING_LLM = ServiceID("anythingllm")

        val QDRANT = ServiceID("qdrant")

        val SEARXNG = ServiceID("searxng")

        /** The assistant that answers in somebody's messengers */
        val OPENCLAW = ServiceID("openclaw")

        /** Services that need a MODEL to be useful at all */
        val MODEL_CONSUMERS: Set<ServiceID> =
            setOf(ServiceID.OPEN_WEB_UI, ServiceID.ANYTHING_LLM, ServiceID.OPENCLAW)

        /** The game engines */
        val GAME_SERVERS: Set<ServiceID> = setOf(MINECRAFT_JAVA, MINECRAFT_BEDROCK)

        /** The user-selectable VPN protocols */
        val VPN_PROTOCOLS: Set<ServiceID> = setOf(
            WIREGUARD_VPN, AMNEZIA_WG, SHADOWSOCKS, XRAY_REALITY, OPEN_VPN
        )
    }
}
