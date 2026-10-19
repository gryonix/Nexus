package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.agentcontrol.AgentChannelGate
import com.skaymer.gryonixnexus.agentcontrol.AgentModOperations
import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.Deployment
import gryonixnexusd.v1.ModFile
import gryonixnexusd.v1.ModFileList
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class ModsViewModel(
    private val scope: CoroutineScope,
    private val operations: suspend (Deployment) -> AgentModOperations?,
    private val release: suspend (Deployment) -> Unit = {},
) {
    data class State(
        val isLoading: Boolean = true,
        val files: List<ModFile> = emptyList(),
        val freeBytes: Long = 0,
        val uploading: Boolean = false,
        val removing: String? = null,
        val errorMessage: String? = null,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    private var job: Job? = null

    fun load(deployment: Deployment) {
        job?.cancel()
        _state.value = State()
        job = scope.launch {
            val mods = operations(deployment) ?: run {
                _state.value = State(isLoading = false, errorMessage = NO_AGENT)
                return@launch
            }
            try {
                apply(mods.files())
            } catch (error: Throwable) {
                _state.value = State(isLoading = false, errorMessage = error.message ?: FAILURE)
            } finally {
                release(deployment)
            }
        }
    }

    fun upload(deployment: Deployment, flavour: String, name: String, content: ByteArray) {
        job?.cancel()
        job = scope.launch {
            _state.value = _state.value.copy(uploading = true, errorMessage = null)
            val mods = operations(deployment) ?: run {
                _state.value = _state.value.copy(uploading = false, errorMessage = NO_AGENT)
                return@launch
            }
            try {
                apply(mods.upload(name, AgentModOperations.slot(flavour), content))
            } catch (error: Throwable) {
                _state.value = _state.value.copy(uploading = false, errorMessage = error.message ?: FAILURE)
            } finally {
                release(deployment)
            }
        }
    }

    fun remove(deployment: Deployment, file: ModFile) {
        job?.cancel()
        job = scope.launch {
            _state.value = _state.value.copy(removing = file.name, errorMessage = null)
            val mods = operations(deployment) ?: run {
                _state.value = _state.value.copy(removing = null, errorMessage = NO_AGENT)
                return@launch
            }
            try {
                apply(mods.delete(file.name, file.slot))
            } catch (error: Throwable) {
                _state.value = _state.value.copy(removing = null, errorMessage = error.message ?: FAILURE)
            } finally {
                release(deployment)
            }
        }
    }

    private fun apply(list: ModFileList) {
        _state.value = _state.value.copy(
            isLoading = false,
            uploading = false,
            removing = null,
            files = list.files,
            freeBytes = list.disk_free_bytes,
        )
    }

    companion object {
        fun canManage(deployment: Deployment): Boolean =
            deployment.usesAgent && deployment.services.contains(ServiceID.MINECRAFT_JAVA)

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
