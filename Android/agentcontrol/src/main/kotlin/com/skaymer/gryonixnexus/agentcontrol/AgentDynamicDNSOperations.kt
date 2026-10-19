package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import gryonixnexusd.v1.DynamicDNSState

class AgentDynamicDNSOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) {
    suspend fun state(): DynamicDNSState = mapping { client.getDynamicDNS() }

    /** Turns it on for [names] */
    suspend fun enable(zone: String, names: List<String>, token: String = ""): DynamicDNSState =
        mapping { client.setDynamicDNS(zone, names, token) }

    /** Turns it off */
    suspend fun disable(): DynamicDNSState =
        mapping { client.setDynamicDNS(zone = "", names = emptyList(), token = "") }

    private suspend fun <T> mapping(body: suspend () -> T): T =
        agentFailure("dynamic-dns") { gate.gated(body) }
}
