package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.PingResult
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.StatusOperations
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface RelayRead<out T> {
    data object Idle : RelayRead<Nothing>
    data object Loading : RelayRead<Nothing>
    data class Loaded<T>(val value: T) : RelayRead<T>
    data class Failed(val message: String) : RelayRead<Nothing>
}

data class RelayStatusState(
    val forwardingVPS: RelayRead<Boolean> = RelayRead.Idle,
    val forwardingHome: RelayRead<Boolean> = RelayRead.Idle,
    val selfPing: RelayRead<PingResult> = RelayRead.Idle,
    val tunnelPing: RelayRead<PingResult> = RelayRead.Idle,
) {
    val forwarding: RelayRead<Boolean>
        get() {
            (forwardingVPS as? RelayRead.Failed)?.let { return it }
            (forwardingHome as? RelayRead.Failed)?.let { return it }
            val vps = forwardingVPS as? RelayRead.Loaded
            val home = forwardingHome as? RelayRead.Loaded
            if (vps != null && home != null) return RelayRead.Loaded(vps.value && home.value)
            if (forwardingVPS is RelayRead.Loading || forwardingHome is RelayRead.Loading) {
                return RelayRead.Loading
            }
            return RelayRead.Idle
        }
}

class RelayStatusViewModel(
    private val scope: CoroutineScope,
    private val runners: suspend (Deployment) -> SSHCommandRunner,
    private val release: suspend (Deployment) -> Unit = {},
) {
    private val _state = MutableStateFlow(RelayStatusState())
    val state: StateFlow<RelayStatusState> = _state.asStateFlow()

    fun forget() {
        _state.value = RelayStatusState()
    }

    /** Asks, once, on demand */
    fun refresh(deployment: Deployment) {
        if (!offered(deployment)) return
        _state.value = RelayStatusState(
            forwardingVPS = RelayRead.Loading,
            forwardingHome = RelayRead.Loading,
            selfPing = RelayRead.Loading,
            tunnelPing = RelayRead.Loading,
        )
        scope.launch {
            val operations = try {
                StatusOperations(runners(deployment), deployment.dashboardConfig)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                fail(reason(failure))
                return@launch
            }
            try {
                val status = operations.generalVPSStatus()
                _state.value = _state.value.copy(
                    forwardingVPS = RelayRead.Loaded(status.forwarding),
                    selfPing = RelayRead.Loaded(status.selfPing),
                    tunnelPing = RelayRead.Loaded(status.tunnelPing),
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                val message = reason(failure)
                _state.value = _state.value.copy(
                    forwardingVPS = RelayRead.Failed(message),
                    selfPing = RelayRead.Failed(message),
                    tunnelPing = RelayRead.Failed(message),
                )
            }
            _state.value = _state.value.copy(
                forwardingHome = try {
                    RelayRead.Loaded(operations.ipForwarding(SSHHostID.HOME))
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (failure: Exception) {
                    release(deployment)
                    RelayRead.Failed(reason(failure))
                }
            )
        }
    }

    private fun fail(message: String) {
        _state.value = RelayStatusState(
            forwardingVPS = RelayRead.Failed(message),
            forwardingHome = RelayRead.Failed(message),
            selfPing = RelayRead.Failed(message),
            tunnelPing = RelayRead.Failed(message),
        )
    }

    private fun reason(failure: Exception): String =
        failure.message ?: failure::class.simpleName ?: "failed"

    companion object {
        fun offered(deployment: Deployment): Boolean = deployment.hasRelayIngress
    }
}
