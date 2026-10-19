package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import com.skaymer.gryonixnexus.servercontrol.ContainerStatus
import com.skaymer.gryonixnexus.servercontrol.OutputTail
import com.skaymer.gryonixnexus.servercontrol.PurgeOptions
import com.skaymer.gryonixnexus.servercontrol.ServiceRemovalManaging
import gryonixnexusd.v1.ServiceOperationPhase

class AgentServiceRemoval(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) : ServiceRemovalManaging {
    /** Removes the service, streaming the wrapper's output */
    override suspend fun remove(
        service: ManagedService,
        purge: PurgeOptions,
        onChunk: (String) -> Unit,
    ): String {
        val id = agentID(service)
        val log = StringBuilder()
        var status: List<ContainerStatus>? = null
        try {
            client.removeService(id, purge.data, purge.backups).collect { event ->
                when (event.phase) {
                    ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS -> {
                        val line = if (event.text.endsWith("\n")) event.text else event.text + "\n"
                        log.append(line)
                        onChunk(line)
                    }

                    ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED ->
                        status = completedStatus(event.status)

                    else -> Unit
                }
            }
        } catch (error: Throwable) {
            val seen = status ?: throw error
            throw AgentControlError.OperationFailed(AgentCommandRunner.asAgentError(error), seen)
        }
        return OutputTail.tail(log.toString())
    }

    private fun agentID(service: ManagedService): String =
        AgentServiceMapping.agentID(service.id)
            ?: throw AgentControlError.UnsupportedService(service.displayName)
}

internal fun completedStatus(status: gryonixnexusd.v1.ServiceStatusResponse?): List<ContainerStatus> {
    if (status == null || !status.installed) return emptyList()
    return status.service?.containers.orEmpty().map(AgentCommandRunner::containerStatus)
}
