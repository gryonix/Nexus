package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.storage.BackupDriveScripts
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import com.skaymer.gryonixnexus.servercontrol.ContainerStatus
import com.skaymer.gryonixnexus.servercontrol.OutputTail
import com.skaymer.gryonixnexus.servercontrol.ServiceRestoreManaging
import gryonixnexusd.v1.ServiceOperationPhase

class AgentRestoreOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) : ServiceRestoreManaging {
    /** Restores the service, streaming the wrapper's output */
    override suspend fun restore(
        service: ManagedService,
        archivePath: String,
        passphrase: String?,
        onChunk: (String) -> Unit,
    ): String {
        val id = agentID(service)
        val staged = staged(archivePath, id)
        val log = StringBuilder()
        var status: List<ContainerStatus>? = null
        try {
            client.runRestore(id, staged, passphrase.orEmpty()).collect { event ->
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

    /** Stages a USB drive copy on the server's disk */
    private suspend fun staged(path: String, serviceID: String): String {
        if (!BackupDriveScripts.isDriveCopy(path)) return path
        return gate.gated { client.fetchDriveBackup(serviceID, path) }.path
    }

    private fun agentID(service: ManagedService): String =
        AgentServiceMapping.agentID(service.id)
            ?: throw AgentControlError.UnsupportedService(service.displayName)
}
