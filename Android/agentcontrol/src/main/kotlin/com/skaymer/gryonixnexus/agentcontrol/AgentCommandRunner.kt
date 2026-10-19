package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import com.skaymer.gryonixnexus.servercontrol.BackupEntry
import com.skaymer.gryonixnexus.servercontrol.ContainerStatus
import com.skaymer.gryonixnexus.servercontrol.ServiceControlling
import com.skaymer.gryonixnexus.servercontrol.ServicePowerAction
import gryonixnexusd.v1.Container
import gryonixnexusd.v1.ServiceAction
import gryonixnexusd.v1.ServiceOperationPhase

class AgentCommandRunner(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) : ServiceControlling {
    override suspend fun status(service: ManagedService): List<ContainerStatus> {
        val id = agentID(service)
        val response = gate.gated { client.serviceStatus(id) }
        if (!response.installed) return emptyList()
        return response.service?.containers.orEmpty().map { containerStatus(it) }
    }

    override suspend fun power(
        action: ServicePowerAction,
        service: ManagedService,
        onProgress: (String) -> Unit,
    ): List<ContainerStatus> {
        val id = agentID(service)
        val wire = wireAction(action)
        return gate.gated {
            var containers: List<ContainerStatus> = emptyList()
            try {
                client.controlService(id, wire).collect { event ->
                    when (event.phase) {
                        ServiceOperationPhase.SERVICE_OPERATION_PHASE_PROGRESS ->
                            onProgress(if (event.text.endsWith("\n")) event.text else event.text + "\n")

                        ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED ->
                            containers = event.service?.containers.orEmpty().map { containerStatus(it) }

                        else -> Unit
                    }
                }
            } catch (error: Throwable) {
                if (containers.isEmpty()) throw error
                throw AgentControlError.OperationFailed(asAgentError(error), containers)
            }
            containers
        }
    }

    private fun agentID(service: ManagedService): String =
        AgentServiceMapping.agentID(service.id)
            ?: throw AgentControlError.UnsupportedService(service.displayName)

    private fun wireAction(action: ServicePowerAction): ServiceAction = when (action) {
        ServicePowerAction.START -> ServiceAction.SERVICE_ACTION_START
        ServicePowerAction.STOP -> ServiceAction.SERVICE_ACTION_STOP
        ServicePowerAction.RESTART -> ServiceAction.SERVICE_ACTION_RESTART
    }

    companion object {
        fun agentID(service: ManagedService): String? = AgentServiceMapping.agentID(service.id)

        internal fun asAgentError(error: Throwable): AgentError =
            error as? AgentError ?: AgentError.Transport(error.toString())

        internal fun containerStatus(container: Container): ContainerStatus {
            val state = container.state.ifEmpty { "unknown" }
            var text = when (state) {
                "running" -> "Up"
                "exited", "dead" -> "Exited"
                else -> state.take(1).uppercase() + state.drop(1)
            }
            if (container.health.isNotEmpty()) text += " (${container.health})"
            return ContainerStatus(container.name, text)
        }
    }
}

sealed class AgentControlError(message: String) : Exception(message) {
    data class UnsupportedService(val name: String) :
        AgentControlError("The server agent does not manage $name yet.")

    data class OperationFailed(
        val underlying: AgentError,
        val status: List<ContainerStatus>,
    ) : AgentControlError(describe(underlying))

    data class BackupFailed(
        val underlying: AgentError,
        val backups: List<BackupEntry>,
    ) : AgentControlError(describe(underlying))

    companion object {
        private fun describe(underlying: AgentError): String =
            (underlying as? AgentError.Rpc)?.text?.takeIf { it.isNotEmpty() }
                ?: underlying.toString()
    }
}
