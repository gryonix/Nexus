package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.DeploymentScope
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

    private val demoID = Regex("6D3E[0-9A-F]{4}-DE40-4000-8000-00000000000[1-4]")

    fun isDemoID(id: String): Boolean = demoID.matches(id)

    /** A handwritten machine's first id, 1 to [SLOTS] */
    fun slotID(slot: Int): String = String.format("6D3E%04X-DE40-4000-8000-%012X", 0, slot)

    fun fleet(requested: Int): List<Deployment> =
        (0 until maxOf(1, requested)).map { index ->
            copy(index / SLOTS)[index % SLOTS]
        }

    private fun copy(copy: Int): List<Deployment> {
        val mark = if (copy == 0) "" else " #${copy + 1}"
        fun id(slot: Int) = String.format("6D3E%04X-DE40-4000-8000-%012X", copy, slot)
        return listOf(busyHost(id(1), mark), relayPair(id(2), mark), localOnly(id(3), mark), sshOnly(id(4), mark))
    }

    private fun busyHost(id: String, mark: String) = Deployment(
        id = id,
        name = "gryonix.com$mark",
        topology = Topology.SINGLE_HOST,
        domain = "gryonix.com",
        entry = HostEndpoint(host = "203.0.113.10", user = "server-user"),
        services = setOf(
            ServiceID.MAILCOW, ServiceID.VAULTWARDEN, ServiceID.NEXTCLOUD, ServiceID.IMMICH,
            ServiceID.WIREGUARD_VPN, ServiceID.AMNEZIA_WG, ServiceID.XRAY_REALITY,
            ServiceID.VPN_PANEL, ServiceID.ADGUARD_HOME,
            ServiceID.HEADSCALE, ServiceID.TAILSCALE_NODE,
            ServiceID.HOMEPAGE, ServiceID.AUTHELIA,
            ServiceID.MINECRAFT_JAVA, ServiceID.CRAFTY_CONTROLLER,
        ),
        tags = listOf("demo"),
        usesAgent = true,
        iconSymbol = "sparkles",
        tintName = ServerTint.TEAL.raw,
    )

    private fun relayPair(id: String, mark: String) = Deployment(
        id = id,
        name = "b.gryonix.com$mark",
        topology = Topology.VPS_RELAY_WITH_HOME_BACKEND,
        domain = "b.gryonix.com",
        entry = HostEndpoint(host = "203.0.113.20", user = "server-user"),
        homeWGAddress = "10.8.0.2",
        services = setOf(
            ServiceID.DOCKER_MAILSERVER, ServiceID.NEXTCLOUD, ServiceID.VAULTWARDEN,
            ServiceID.WIREGUARD_VPN, ServiceID.SHADOWSOCKS, ServiceID.XRAY_REALITY,
            ServiceID.OPEN_VPN, ServiceID.VPN_PANEL,
        ),
        tags = listOf("demo"),
        usesAgent = true,
        tintName = ServerTint.PURPLE.raw,
    )

    private fun localOnly(id: String, mark: String) = Deployment(
        id = id,
        name = "home.local$mark",
        topology = Topology.SINGLE_HOST,
        domain = "home.local",
        entry = HostEndpoint(host = "192.168.1.24", user = "server-user"),
        services = setOf(ServiceID.SEAFILE, ServiceID.PHOTOPRISM, ServiceID.JELLYFIN, ServiceID.PIHOLE),
        tags = listOf("demo"),
        usesAgent = true,
        iconSymbol = "house.fill",
        tintName = ServerTint.GREEN.raw,
        scope = DeploymentScope.LOCAL_ONLY,
    )

    private fun sshOnly(id: String, mark: String) = Deployment(
        id = id,
        name = "lab.gryonix.com$mark",
        topology = Topology.SINGLE_HOST,
        domain = "lab.gryonix.com",
        entry = HostEndpoint(host = "203.0.113.30", user = "server-user"),
        services = setOf(
            ServiceID.FORGEJO, ServiceID.PSONO, ServiceID.WIREGUARD_VPN, ServiceID.AMNEZIA_WG,
            ServiceID.VPN_PANEL,
        ),
        tags = listOf("demo"),
        tintName = ServerTint.ORANGE.raw,
    )
}
