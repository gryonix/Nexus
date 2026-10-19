package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationKind
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import gryonixnexusd.v1.AgentUpdateStatus
import gryonixnexusd.v1.JobPhase
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class AgentSelfUpdateState(
    val status: AgentUpdateStatus? = null,
    val isApplying: Boolean = false,
    val progress: String? = null,
    val errorMessage: String? = null,
)

class AgentSelfUpdateViewModel(
    private val scope: CoroutineScope,
    private val client: suspend (Deployment) -> AgentClient?,
    /** The agent on one particular machine of a server */
    private val hostClient: suspend (Deployment, SSHHostID) -> AgentClient? = { deployment, _ -> client(deployment) },
) {
    private val _state = MutableStateFlow(AgentSelfUpdateState())
    val state: StateFlow<AgentSelfUpdateState> = _state.asStateFlow()

    fun load(deployment: Deployment) {
        scope.launch {
            val agent = client(deployment) ?: return@launch
            val status = try {
                agent.getAgentUpdateStatus()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                return@launch
            }
            _state.value = _state.value.copy(status = status)
        }
    }

    /** Switches automatic agent updates on every machine of the server */
    fun setAutoUpdate(deployment: Deployment, enabled: Boolean) {
        scope.launch {
            for (host in deployment.agentHosts) {
                val status = try {
                    hostClient(deployment, host)?.setAgentAutoUpdate(enabled) ?: continue
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (failure: Exception) {
                    continue
                }
                if (host == deployment.servicesHost) _state.value = _state.value.copy(status = status)
            }
        }
    }

    fun apply(deployment: Deployment) {
        if (_state.value.isApplying) return
        _state.value = _state.value.copy(isApplying = true, errorMessage = null, progress = "Starting…")
        scope.launch {
            val agent = client(deployment)
            if (agent == null) {
                _state.value = _state.value.copy(
                    isApplying = false,
                    errorMessage = "This server is not managed over a real connection.",
                )
                return@launch
            }
            var failed: String? = null
            var heardFromAgent = false
            val notice = OperationNotices.start(R.string.notice_updating_agent, server = deployment.name, kind = OperationKind.UPDATE)
            try {
                agent.applyAgentUpdate().collect { event ->
                    heardFromAgent = true
                    if (event.text.isNotEmpty()) {
                        _state.value = _state.value.copy(progress = event.text)
                        notice.update(event.text)
                    }
                    if (event.phase == JobPhase.JOB_PHASE_FAILED) {
                        failed = event.reason.ifEmpty { "The update failed." }
                    }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                if (!heardFromAgent) failed = failure.message ?: failure.toString()
            }
            if (failed != null) {
                _state.value = _state.value.copy(isApplying = false, errorMessage = failed)
                notice.finish("", failed)
                return@launch
            }
            _state.value = _state.value.copy(progress = "The agent is restarting…")
            delay(5_000)
            val agentAgain = client(deployment)
            val status = agentAgain?.let {
                try {
                    it.getAgentUpdateStatus()
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (failure: Exception) {
                    null
                }
            }
            _state.value = _state.value.copy(
                isApplying = false,
                status = status ?: _state.value.status,
                errorMessage = when {
                    status == null -> OperationNotices.text(R.string.agent_no_answer_after_restart)
                    !status.last_apply_succeeded -> status.last_apply_reason
                    else -> null
                },
            )
            notice.finish(OperationNotices.text(R.string.notice_done), _state.value.errorMessage)
        }
    }
}
