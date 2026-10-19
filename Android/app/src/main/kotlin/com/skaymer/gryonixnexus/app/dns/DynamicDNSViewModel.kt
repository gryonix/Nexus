package com.skaymer.gryonixnexus.app.dns

import com.skaymer.gryonixnexus.agentcontrol.AgentDynamicDNSOperations
import com.skaymer.gryonixnexus.servercontrol.Deployment
import gryonixnexusd.v1.DynamicDNSState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the dynamic-DNS screen is showing about one server */
data class DynamicDNSScreenState(
    /** What the HOST says it is keeping current */
    val state: DynamicDNSState? = null,
    val isWorking: Boolean = false,
    val errorMessage: String? = null,
)

class DynamicDNSViewModel(
    private val scope: CoroutineScope,
    private val operations: suspend (Deployment) -> AgentDynamicDNSOperations,
    private val release: suspend (Deployment) -> Unit = {},
) {
    private val _state = MutableStateFlow(DynamicDNSScreenState())
    val state: StateFlow<DynamicDNSScreenState> = _state.asStateFlow()

    fun load(deployment: Deployment) {
        scope.launch { call(deployment) { it.state() } }
    }

    fun save(deployment: Deployment, zone: String, names: List<String>, token: String) {
        scope.launch {
            call(deployment) { operations ->
                if (names.isEmpty()) operations.disable() else operations.enable(zone, names, token)
            }
        }
    }

    fun reset() {
        _state.value = DynamicDNSScreenState()
    }

    private suspend fun call(
        deployment: Deployment,
        body: suspend (AgentDynamicDNSOperations) -> DynamicDNSState,
    ) {
        _state.value = _state.value.copy(isWorking = true, errorMessage = null)
        try {
            _state.value = DynamicDNSScreenState(state = body(operations(deployment)))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            release(deployment)
            _state.value = _state.value.copy(
                isWorking = false,
                errorMessage = failure.message ?: failure::class.simpleName,
            )
        }
    }

    companion object {
        /** Can this server keep its own records current? */
        fun canManage(deployment: Deployment, agentTransportAvailable: Boolean = true): Boolean =
            deployment.usesAgent && agentTransportAvailable

        fun names(text: String): List<String> =
            text.lines().map { it.trim() }.filter { it.isNotEmpty() }

        fun canSave(zone: String, names: List<String>, token: String, hasStoredToken: Boolean): Boolean {
            if (zone.trim().isEmpty() || names.isEmpty()) return false
            return hasStoredToken || token.isNotEmpty()
        }
    }
}
