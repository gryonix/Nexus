package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.servercontrol.DKIMManaging
import com.skaymer.gryonixnexus.servercontrol.DKIMRecord
import com.skaymer.gryonixnexus.servercontrol.ServerControlError

class AgentDkimOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) : DKIMManaging {
    override suspend fun fetchRecords(): List<DKIMRecord> =
        agentFailure("dkim") {
            gate.gated { client.getDkimRecords() }.map { DKIMRecord(it.name, it.value_) }
        }
}

internal suspend fun <T> agentFailure(label: String, body: suspend () -> T): T =
    try {
        body()
    } catch (error: AgentError.Rpc) {
        if (error.text.isEmpty()) throw error
        throw ServerControlError.CommandFailed(label, null, error.text)
    }
