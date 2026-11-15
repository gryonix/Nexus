package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient

class AgentExposure(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) {
    /** The requested ports that answer on the server's public address */
    suspend fun openPorts(host: String, ports: List<Int>): List<Int> = agentFailure("exposure") {
        gate.gated { client.probePublicPorts(host, ports) }.ports.filter { it.open_ }.map { it.port }
    }

    /** Caddy's local root certificate, PEM; empty when it has none */
    suspend fun localRootCA(): String = agentFailure("exposure") { gate.gated { client.getLocalRootCA() } }

    /** Module ids the server keeps on */
    suspend fun appModules(): List<String> = agentFailure("modules") { gate.gated { client.getAppModules() } }

    suspend fun setAppModules(on: List<String>): List<String> =
        agentFailure("modules") { gate.gated { client.setAppModules(on) } }

    /** Reads the service names, or names one service */
    suspend fun serviceNames(named: Pair<String, String>? = null): Map<String, String> = agentFailure("names") {
        gate.gated { if (named == null) client.getServiceNames() else client.setServiceName(named.first, named.second) }
    }

    /** The machine's sound outputs, default first */
    suspend fun audioOutputs(): List<gryonixnexusd.v1.AudioOutput> =
        agentFailure("audio") { gate.gated { client.listAudioOutputs() } }

    /** Reads .local names, or sets one for a host */
    suspend fun localAliases(host: String?, on: Boolean): Map<String, String> = agentFailure("exposure") {
        gate.gated { if (host == null) client.getLocalAliases() else client.setLocalAlias(host, on) }
    }

    /** Keeps these ports to private addresses; empty clears */
    suspend fun setHomeOnlyPorts(ports: List<Pair<String, Int>>) =
        agentFailure("exposure") { gate.gated { client.setHomeOnlyPorts(ports) } }

    /** Reads the MCP door, or sets it with a key */
    suspend fun mcpAccess(enabled: Boolean?, publicKey: String): gryonixnexusd.v1.McpAccessState = agentFailure("mcp") {
        gate.gated { if (enabled == null) client.getMcpAccess() else client.setMcpAccess(enabled, publicKey) }
    }

    /** One call to the audio hub's API; non-2xx throws */
    suspend fun odio(method: String, path: String, body: String = ""): String {
        val reply = agentFailure("audio") { gate.gated { client.odioCall(method, path, body) } }
        check(reply.status in 200..299) { reply.body.ifEmpty { "odio-api: ${reply.status}" } }
        return reply.body
    }
}
