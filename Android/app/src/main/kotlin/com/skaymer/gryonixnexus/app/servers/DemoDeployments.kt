package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint

/** A synthetic fleet for design work and screenshots */
object DemoDeployments {
    /** The number of handwritten machines; past this the fleet REPEATS */
    const val SLOTS = 4

    /** The stored count */
    const val COUNT_KEY = "demo.servers"

    /** A full demo fleet */
    const val FULL_COUNT = "8"

    private val demoID = Regex("[0-9A-F]{8}-0000-0000-0000-0000000000[A-Z0-9]{2}")

    fun isDemoID(id: String): Boolean = demoID.matches(id)

    fun fleet(requested: Int): List<Deployment> =
        (0 until maxOf(1, requested)).map { index ->
            copy(index / SLOTS)[index % SLOTS]
        }

    private fun copy(copy: Int): List<Deployment> {
        val mark = if (copy == 0) "" else " #${copy + 1}"
        fun id(slot: String) = String.format("%08X-0000-0000-0000-0000000000%s", copy, slot)
        return listOf(
            Deployment(
                id = id("A1"),
                name = "example.net$mark",
                topology = Topology.SINGLE_HOST,
                domain = "example.net",
                entry = HostEndpoint(host = "203.0.113.10", user = "server-user"),
                services = setOf(
                    ServiceID.MAILCOW, ServiceID.VAULTWARDEN, ServiceID.NEXTCLOUD,
                    ServiceID.WIREGUARD_VPN, ServiceID.VPN_PANEL,
                    ServiceID.HEADSCALE, ServiceID.TAILSCALE_NODE
                ),
                tags = listOf("prod"),
                usesAgent = true,
                tintName = ServerTint.TEAL.raw
            ),
            Deployment(
                id = id("B2"),
                name = "b5.example.net$mark",
                topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
                domain = "b5.example.net",
                additionalDomains = listOf("b6.example.net"),
                entry = HostEndpoint(host = "203.0.113.20", user = "server-user"),
                homeWGAddress = "10.8.0.2",
                services = setOf(
                    ServiceID.DOCKER_MAILSERVER, ServiceID.VAULTWARDEN,
                    ServiceID.WIREGUARD_VPN, ServiceID.VPN_PANEL,
                    ServiceID.HOME_ASSISTANT, ServiceID.MOSQUITTO, ServiceID.ZIGBEE2MQTT
                ),
                serviceSettings = ServiceSettings(
                    homeAssistantUSBDevice =
                        "/dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus-if00-port0"
                ),
                tags = listOf("prod", "home"),
                tintName = ServerTint.PURPLE.raw
            ),
            Deployment(
                id = id("C3"),
                name = "lab.gryonix.com$mark",
                topology = Topology.SINGLE_HOST,
                domain = "lab.gryonix.com",
                entry = HostEndpoint(host = "203.0.113.30", user = "server-user"),
                services = setOf(ServiceID.IMMICH, ServiceID.FORGEJO),
                tags = listOf("lab"),
                tintName = ServerTint.ORANGE.raw
            ),
            Deployment(
                id = id("D4"),
                name = "orion$mark",
                topology = Topology.SINGLE_HOST,
                domain = "orion.local",
                entry = HostEndpoint(host = "192.168.178.100", user = "admin"),
                services = setOf(ServiceID.NEXTCLOUD),
                tags = listOf("lab"),
                tintName = ServerTint.GREEN.raw
            )
        )
    }
}
