package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.catalog.ServiceID
import gryonixnexusd.v1.VpnClient
import gryonixnexusd.v1.VpnDns
import gryonixnexusd.v1.VpnDnsPriority
import gryonixnexusd.v1.VpnState

/** One VPN client device, in the app's own vocabulary */
data class VPNClientDevice(
    val id: String,
    val name: String,
    val detail: String,
    val dns: List<String> = emptyList(),
)

/** A client's configuration as its own app imports it */
data class VPNClientConfiguration(
    val text: String,
    val fileName: String,
    val qrIsUseful: Boolean,
    /** What a proxy link cannot carry itself */
    val dns: List<String> = emptyList(),
)

/** The DNS new devices get, and the server's own resolver */
data class VPNDNSDefaults(
    val dns: List<String> = emptyList(),
    /** Where the server's resolver answers; empty when it cannot */
    val localAddress: String = "",
    /** AdGuard Home or Pi-hole, when devices can reach them */
    val localServices: List<ServiceID> = emptyList(),
) {
    companion object {
        fun of(proto: VpnDns) = VPNDNSDefaults(proto.dns, proto.local_address, proto.local_services.map(::ServiceID))
    }
}

/** The order the server's DNS relay asks resolvers in */
data class VPNDNSPriority(
    val resolvers: List<String> = listOf(LOCAL, "1.1.1.1"),
    /** Whether a resolver stands behind [LOCAL] */
    val localAvailable: Boolean = false,
    /** Per resolver: whether it answered lately */
    val reachable: List<Boolean> = emptyList(),
) {
    /** Whether the resolver at this position answered lately */
    fun isReachable(index: Int): Boolean = reachable.getOrNull(index) ?: true

    companion object {
        /** The entry for the deployment's own resolver */
        const val LOCAL = "local"

        fun of(proto: VpnDnsPriority) = VPNDNSPriority(proto.resolvers, proto.local_available, proto.reachable)
    }
}

class AgentVPNClientOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) {
    suspend fun list(protocol: ServiceID): List<VPNClientDevice> =
        run { client.listVPNClients(protocol.rawValue) }

    suspend fun add(protocol: ServiceID, named: String, dns: List<String> = emptyList()): List<VPNClientDevice> =
        run { client.addVPNClient(protocol.rawValue, named, dns) }

    suspend fun setDNS(protocol: ServiceID, clientID: String, dns: List<String>): List<VPNClientDevice> =
        run { client.setVPNClientDNS(protocol.rawValue, clientID, dns) }

    suspend fun defaultDNS(): VPNDNSDefaults = VPNDNSDefaults.of(gate.gated { client.vpnDefaultDNS() })

    suspend fun setDefaultDNS(dns: List<String>): VPNDNSDefaults =
        VPNDNSDefaults.of(gate.gated { client.setVPNDefaultDNS(dns) })

    suspend fun dnsPriority(): VPNDNSPriority = VPNDNSPriority.of(gate.gated { client.vpnDNSPriority() })

    suspend fun setDNSPriority(resolvers: List<String>): VPNDNSPriority =
        VPNDNSPriority.of(gate.gated { client.setVPNDNSPriority(resolvers) })

    /** The VPN's directories, packed on this machine */
    suspend fun exportState(directories: List<String>): VpnState = gate.gated { client.exportVPNState(directories) }

    /** Unpacks another machine's VPN directories here */
    suspend fun importState(state: VpnState, replace: Boolean): List<String> =
        gate.gated { client.importVPNState(state, replace) }.directories

    suspend fun remove(protocol: ServiceID, clientID: String): List<VPNClientDevice> =
        run { client.deleteVPNClient(protocol.rawValue, clientID) }

    suspend fun configuration(protocol: ServiceID, clientID: String): VPNClientConfiguration {
        val response = gate.gated { client.vpnClientConfig(protocol.rawValue, clientID) }
        return VPNClientConfiguration(
            text = response.text,
            fileName = response.filename,
            qrIsUseful = response.qr_is_useful,
            dns = response.dns,
        )
    }

    private suspend fun run(call: suspend () -> List<VpnClient>): List<VPNClientDevice> =
        gate.gated(call).map { VPNClientDevice(it.id, it.name, it.detail, it.dns) }
}

/** Which catalog services can have client devices at all */
object VPNClientProtocols {
    val all: List<ServiceID> = listOf(
        ServiceID.WIREGUARD_VPN,
        ServiceID.AMNEZIA_WG,
        ServiceID.SHADOWSOCKS,
        ServiceID.XRAY_REALITY,
        ServiceID.OPEN_VPN,
    )

    fun installed(services: Set<ServiceID>): List<ServiceID> = all.filter { it in services }
}
