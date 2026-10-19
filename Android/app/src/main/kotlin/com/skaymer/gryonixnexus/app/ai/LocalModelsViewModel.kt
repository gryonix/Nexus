package com.skaymer.gryonixnexus.app.ai

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.Deployment
import gryonixnexusd.v1.Model
import gryonixnexusd.v1.ModelList
import gryonixnexusd.v1.ServiceOperationPhase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class LocalModelsViewModel(
    private val scope: CoroutineScope,
    private val client: suspend (Deployment) -> AgentClient?,
    private val release: suspend (Deployment) -> Unit = {},
) {
    data class State(
        val isLoading: Boolean = true,
        val enginePresent: Boolean = false,
        val models: List<Model> = emptyList(),
        val path: String = "",
        val freeBytes: Long = 0,
        val totalBytes: Long = 0,
        val pull: Pull? = null,
        val removing: String? = null,
        val errorMessage: String? = null,
    )

    data class Pull(
        val text: String = "",
        val completed: Long = 0,
        val total: Long = 0,
        val jobID: String = "",
        /** True from the tap until the run reports back */
        val stopping: Boolean = false,
    ) {
        val fraction: Float? get() = if (total > 0) (completed.toFloat() / total).coerceIn(0f, 1f) else null
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    private var job: Job? = null

    fun load(deployment: Deployment) {
        job?.cancel()
        _state.value = State()
        job = scope.launch {
            val agent = client(deployment) ?: run {
                _state.value = State(isLoading = false, errorMessage = NO_AGENT)
                return@launch
            }
            try {
                apply(agent.listModels())
            } catch (error: Throwable) {
                _state.value = State(isLoading = false, errorMessage = error.message ?: FAILURE)
            } finally {
                release(deployment)
            }
        }
    }

    fun fetch(deployment: Deployment, name: String) {
        val wanted = name.trim()
        if (wanted.isEmpty()) return
        job?.cancel()
        job = scope.launch {
            _state.value = _state.value.copy(pull = Pull(), errorMessage = null)
            val agent = client(deployment) ?: run {
                _state.value = _state.value.copy(pull = null, errorMessage = NO_AGENT)
                return@launch
            }
            var problem: String? = null
            val notice = OperationNotices.start(R.string.notice_fetching, wanted, server = deployment.name)
            try {
                agent.pullModel(wanted).collect { event ->
                    if (event.phase == ServiceOperationPhase.SERVICE_OPERATION_PHASE_COMPLETED) {
                        event.list?.let { apply(it) }
                        if (event.text.isNotEmpty() &&
                            _state.value.models.none { it.name == wanted }
                        ) {
                            problem = event.text
                        }
                    } else {
                        notice.update(event.text, event.completed_bytes.toDouble() / event.total_bytes.coerceAtLeast(1))
                        _state.value = _state.value.copy(
                            pull = Pull(
                                text = event.text,
                                completed = event.completed_bytes,
                                total = event.total_bytes,
                                jobID = event.job_id,
                                stopping = _state.value.pull?.stopping == true,
                            ),
                        )
                    }
                }
            } catch (error: Throwable) {
                problem = error.message ?: FAILURE
            } finally {
                release(deployment)
            }
            _state.value = _state.value.copy(pull = null, errorMessage = problem)
            notice.finish(OperationNotices.text(R.string.notice_done), problem)
        }
    }

    /** Ask the host to stop the fetch that is running */
    fun stop(deployment: Deployment) {
        val running = _state.value.pull ?: return
        if (running.jobID.isEmpty() || running.stopping) return
        _state.value = _state.value.copy(pull = running.copy(stopping = true), errorMessage = null)
        scope.launch {
            val agent = client(deployment) ?: run {
                _state.value = _state.value.copy(
                    pull = _state.value.pull?.copy(stopping = false),
                    errorMessage = NO_AGENT,
                )
                return@launch
            }
            try {
                agent.cancelJob(running.jobID)
            } catch (error: Throwable) {
                _state.value = _state.value.copy(
                    pull = _state.value.pull?.copy(stopping = false),
                    errorMessage = error.message ?: FAILURE,
                )
            } finally {
                release(deployment)
            }
        }
    }

    fun remove(deployment: Deployment, name: String) {
        job?.cancel()
        job = scope.launch {
            _state.value = _state.value.copy(removing = name, errorMessage = null)
            val agent = client(deployment) ?: run {
                _state.value = _state.value.copy(removing = null, errorMessage = NO_AGENT)
                return@launch
            }
            try {
                apply(agent.deleteModel(name))
            } catch (error: Throwable) {
                _state.value = _state.value.copy(removing = null, errorMessage = error.message ?: FAILURE)
            } finally {
                release(deployment)
            }
        }
    }

    private fun apply(list: ModelList) {
        _state.value = _state.value.copy(
            isLoading = false,
            enginePresent = list.engine_present,
            models = list.models,
            path = list.path,
            freeBytes = list.disk_free_bytes,
            totalBytes = list.disk_total_bytes,
            removing = null,
        )
    }

    companion object {
        fun canManage(deployment: Deployment): Boolean =
            deployment.usesAgent && deployment.services.contains(ServiceID.OLLAMA)

        const val NO_AGENT = "no_agent"
        const val FAILURE = "failure"

        /** Bytes as a person reads them */
        fun human(bytes: Long): String {
            val gb = 1_073_741_824.0
            val mb = 1_048_576.0
            val value = bytes.toDouble()
            return when {
                value >= gb -> String.format("%.1f GB", value / gb)
                value >= mb -> String.format("%.0f MB", value / mb)
                else -> "$bytes B"
            }
        }
    }
}
