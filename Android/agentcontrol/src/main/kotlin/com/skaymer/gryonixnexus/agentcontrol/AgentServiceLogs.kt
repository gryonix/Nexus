package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Follows every container of ONE catalogue service, live */
class AgentServiceLogs(private val client: AgentClient) {
    fun logs(agentServiceID: String, tail: Int = 200): Flow<ContainerLogLine> =
        client.logs(agentServiceID, tail).map {
            ContainerLogLine(container = it.container, text = it.text, stream = it.stream)
        }
}
