package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentcontrol.AgentAdminLockdown
import com.skaymer.gryonixnexus.agentcontrol.AgentChannelGate
import com.skaymer.gryonixnexus.agentcontrol.AgentServiceRemoval
import com.skaymer.gryonixnexus.agentcontrol.AgentVPNClientOperations
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.PurgeOptions
import com.skaymer.gryonixnexus.servercontrol.restore
import kotlinx.coroutines.CancellationException
import gryonixnexusd.v1.VpnState

/** One machine's agent, as a side of a VPN move */
class AgentVPNMoveMachine(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) : VPNMoveMachine {
    private val vpn = AgentVPNClientOperations(client, gate)

    override suspend fun pack(directories: List<String>): VpnState = vpn.exportState(directories)

    override suspend fun unpack(state: VpnState, replace: Boolean) {
        vpn.importState(state, replace)
    }

    /** Stops the VPN here, its data and panel guard kept */
    override suspend fun removeVPN() {
        val panel = ServiceRegistry.service(ServiceID.VPN_PANEL) ?: return
        val lockdown = AgentAdminLockdown(client, gate)
        val kept = quietly { lockdown.status() }
        AgentServiceRemoval(client, gate).remove(panel, PurgeOptions.NONE) {}
        if (kept?.isActive == true) quietly { lockdown.restore(kept) }
    }

    private suspend fun <T> quietly(block: suspend () -> T): T? = try {
        block()
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        null
    }
}
