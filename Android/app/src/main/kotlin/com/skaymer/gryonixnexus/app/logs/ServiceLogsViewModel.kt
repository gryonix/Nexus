package com.skaymer.gryonixnexus.app.logs

import com.skaymer.gryonixnexus.agentcontrol.ContainerLogLine
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRouting
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ServiceLogLine(
    val container: String,
    val text: String,
    val stream: String,
) {
    val shortContainer: String
        get() {
            val parts = container.split("-")
            return if (parts.size > 2) parts.drop(1).dropLast(1).joinToString("-") else container
        }
}

/** How far a read got */
enum class ServiceLogsStatus { CONNECTING, FOLLOWING, ENDED, FAILED }

/** Which of the two reads this is */
enum class ServiceLogsKind { LIVE, SNAPSHOT }

/** What the log screen is showing about one service */
data class ServiceLogsState(
    val lines: List<ServiceLogLine> = emptyList(),
    val containers: List<String> = emptyList(),
    val status: ServiceLogsStatus = ServiceLogsStatus.CONNECTING,
    val errorMessage: String? = null,
    val kind: ServiceLogsKind = ServiceLogsKind.SNAPSHOT,
    /** null = every container */
    val filter: String? = null,
) {
    val isLive: Boolean get() = kind == ServiceLogsKind.LIVE

    val visible: List<ServiceLogLine>
        get() = filter?.let { name -> lines.filter { it.container == name } } ?: lines

    val saysThereIsNoOutput: Boolean
        get() = status == ServiceLogsStatus.ENDED && errorMessage == null && lines.isEmpty()

    fun plainText(): String = visible.joinToString("\n") { line ->
        if (filter == null && containers.size > 1 && line.container.isNotEmpty()) {
            "[${line.shortContainer}] ${line.text}"
        } else {
            line.text
        }
    }
}

/** Which route reads this service's log */
object ServiceLogsRouting {
    fun route(
        usesAgent: Boolean,
        agentTransportAvailable: Boolean,
        agentServiceID: String?,
    ): ServiceControlRoute {
        if (agentServiceID == null) return ServiceControlRoute.SSH
        return ServiceControlRouting.route(usesAgent, agentTransportAvailable)
    }
}

class ServiceLogsViewModel(
    private val scope: CoroutineScope,
    private val streams: (Deployment, String) -> Flow<ContainerLogLine>,
    /** One bounded tail over SSH */
    private val snapshots: suspend (Deployment, ManagedService) -> List<String>,
    private val agentTransportAvailable: Boolean = true,
) {
    private val _state = MutableStateFlow(ServiceLogsState())
    val state: StateFlow<ServiceLogsState> = _state.asStateFlow()

    private var job: Job? = null
    private var open: Pair<Deployment, ManagedService>? = null

    companion object {
        /** A live follow is unbounded; the buffer is not */
        const val BUFFER_LIMIT = 2000

        const val TAIL = 200
    }

    /** Start reading */
    fun start(deployment: Deployment, service: ManagedService) {
        if (job != null) return
        open = deployment to service
        val agentID = AgentServiceMapping.agentID(service.id)
        val route = ServiceLogsRouting.route(
            usesAgent = deployment.usesAgent,
            agentTransportAvailable = agentTransportAvailable,
            agentServiceID = agentID,
        )
        _state.value = ServiceLogsState(
            kind = if (route == ServiceControlRoute.AGENT) {
                ServiceLogsKind.LIVE
            } else {
                ServiceLogsKind.SNAPSHOT
            },
        )
        job = scope.launch {
            try {
                if (route == ServiceControlRoute.AGENT && agentID != null) {
                    follow(deployment, agentID)
                } else {
                    snapshot(deployment, service)
                }
                finish(null)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                finish(failure.message ?: failure::class.simpleName)
            }
        }
    }

    /** Ask for the tail again, REPLACING what is on screen */
    fun reload() {
        val (deployment, service) = open ?: return
        if (_state.value.kind != ServiceLogsKind.SNAPSHOT) return
        job?.cancel()
        job = null
        _state.value = _state.value.copy(
            lines = emptyList(),
            containers = emptyList(),
            status = ServiceLogsStatus.CONNECTING,
            errorMessage = null,
        )
        job = scope.launch {
            try {
                snapshot(deployment, service)
                finish(null)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                finish(failure.message ?: failure::class.simpleName)
            }
        }
    }

    /** Show one container's lines, or all of them again */
    fun filter(container: String?) {
        _state.value = _state.value.copy(filter = container)
    }

    fun close() {
        job?.cancel()
        job = null
        open = null
        _state.value = ServiceLogsState()
    }

    private suspend fun follow(deployment: Deployment, agentServiceID: String) {
        _state.value = _state.value.copy(status = ServiceLogsStatus.FOLLOWING)
        streams(deployment, agentServiceID).collect { line ->
            append(ServiceLogLine(line.container, line.text, line.stream))
        }
    }

    private suspend fun snapshot(deployment: Deployment, service: ManagedService) {
        val lines = snapshots(deployment, service)
        lines.forEach { append(ServiceLogLine(container = "", text = it, stream = "stdout")) }
    }

    private fun append(line: ServiceLogLine) {
        val current = _state.value
        val grown = current.lines + line
        val trimmed = if (grown.size <= BUFFER_LIMIT) {
            grown
        } else {
            grown.subList(grown.size - BUFFER_LIMIT, grown.size)
        }
        val containers = if (line.container.isEmpty() || line.container in current.containers) {
            current.containers
        } else {
            (current.containers + line.container).sorted()
        }
        _state.value = current.copy(lines = trimmed, containers = containers)
    }

    private fun finish(errorMessage: String?) {
        _state.value = _state.value.copy(
            status = if (errorMessage == null) {
                ServiceLogsStatus.ENDED
            } else {
                ServiceLogsStatus.FAILED
            },
            errorMessage = errorMessage,
        )
    }
}
