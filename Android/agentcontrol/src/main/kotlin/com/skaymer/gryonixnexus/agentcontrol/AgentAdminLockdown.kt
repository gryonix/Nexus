package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.servercontrol.AdminLockdownManaging
import com.skaymer.gryonixnexus.servercontrol.AdminLockdownState
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import gryonixnexusd.v1.LockdownMode
import gryonixnexusd.v1.LockdownState

class AgentAdminLockdown(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) : AdminLockdownManaging {
    override suspend fun status(): AdminLockdownState =
        mapping { state(client.getLockdown()) }

    override suspend fun set(enabled: Boolean): AdminLockdownState = mapping {
        state(
            client.setLockdown(
                if (enabled) LockdownMode.LOCKDOWN_MODE_ALL else LockdownMode.LOCKDOWN_MODE_OFF,
            ),
        )
    }

    override suspend fun set(hosts: List<String>): AdminLockdownState {
        if (hosts.isEmpty()) return set(false)
        val invalid = hosts.filterNot { CommandCatalog.AdminLockdown.isValidHost(it) }
        if (invalid.isNotEmpty()) {
            throw ServerControlError.CommandFailed(
                "lockdown",
                null,
                "These names cannot be guarded: ${invalid.joinToString(", ")}. Nothing was changed.",
            )
        }
        return mapping { state(client.setLockdown(LockdownMode.LOCKDOWN_MODE_ONLY, hosts)) }
    }

    // --------------------------------------------------------------- Helpers

    private fun state(proto: LockdownState): AdminLockdownState = when (proto.mode) {
        LockdownMode.LOCKDOWN_MODE_ALL -> AdminLockdownState.All
        LockdownMode.LOCKDOWN_MODE_ONLY -> AdminLockdownState.Only(proto.hosts.toSet())
        else -> AdminLockdownState.Off
    }

    private suspend fun <T> mapping(body: suspend () -> T): T =
        agentFailure("lockdown") { gate.gated(body) }
}
