package com.skaymer.gryonixnexus.agentcontrol

import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/** Caps how many agent RPCs are in flight at once */
class AgentChannelGate(limit: Int = DEFAULT_LIMIT) {
    private val slots = Semaphore(maxOf(1, limit))

    suspend fun <T> withSlot(body: suspend () -> T): T = slots.withPermit { body() }

    companion object {
        const val DEFAULT_LIMIT = 4

        private val registry = ConcurrentHashMap<String, AgentChannelGate>()

        fun shared(deploymentID: String): AgentChannelGate =
            registry.computeIfAbsent(deploymentID) { AgentChannelGate() }
    }
}

internal suspend fun <T> AgentChannelGate?.gated(body: suspend () -> T): T =
    if (this == null) body() else withSlot(body)
