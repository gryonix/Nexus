package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import gryonixnexusd.v1.OpenAPIState

/** One service's paths open past the VPN guard */
data class OpenAPISite(val serviceID: String, val paths: List<String>, val editable: Boolean)

/** Reads and changes which API paths answer without the VPN */
interface OpenAPIAccess {
    suspend fun sites(): Map<String, OpenAPISite>
    suspend fun set(serviceID: String, paths: List<String>): Map<String, OpenAPISite>
}

class AgentOpenAPI(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) : OpenAPIAccess {
    override suspend fun sites(): Map<String, OpenAPISite> =
        agentFailure("open API") { gate.gated { sites(client.getOpenAPI()) } }

    override suspend fun set(serviceID: String, paths: List<String>): Map<String, OpenAPISite> =
        agentFailure("open API") { gate.gated { sites(client.setOpenAPI(serviceID, paths)) } }

    companion object {
        fun sites(state: OpenAPIState): Map<String, OpenAPISite> =
            state.sites.associate { it.service_id to OpenAPISite(it.service_id, it.paths, it.editable) }
    }
}
