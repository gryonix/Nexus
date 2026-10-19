package com.skaymer.gryonixnexus.app.devices

import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.agentcontrol.AgentDeviceOperations
import com.skaymer.gryonixnexus.servercontrol.Deployment
import gryonixnexusd.v1.Device
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the paired-devices screen is showing for one server */
data class DevicesState(
    val devices: List<Device> = emptyList(),
    val isLoading: Boolean = true,
    val failure: String? = null,
    val needsSignIn: Boolean = false,
    val signingIn: Boolean = false,
    val signInError: String? = null,
    /** 0 (never), 1, 3, 6 or 12 */
    val autoLogoutMonths: Int = 0,
    val savingPolicy: Boolean = false,
    val policyError: String? = null,
    val revoking: String? = null,
    val revokeError: String? = null,
)

class DevicesViewModel(
    private val scope: CoroutineScope,
    private val operations: suspend (Deployment) -> AgentDeviceOperations,
    private val thisDeviceUID: () -> String = { "" },
    private val release: suspend (Deployment) -> Unit = {},
    private val enrol: suspend (Deployment) -> Unit = { error("Pairing unavailable") },
) {
    private val _state = MutableStateFlow(DevicesState())
    val state: StateFlow<DevicesState> = _state.asStateFlow()

    private var job: Job? = null

    fun load(deployment: Deployment) {
        job?.cancel()
        _state.value = DevicesState()
        job = scope.launch {
            try {
                val ops = operations(deployment)
                val listed = ops.listDevices().sortedBy { it.paired_at }
                val months = runCatching { ops.sessionPolicy().auto_logout_months }.getOrDefault(0)
                _state.value = DevicesState(
                    devices = listed,
                    isLoading = false,
                    autoLogoutMonths = months,
                )
            } catch (error: Throwable) {
                val signedOut = isSignedOut(error)
                _state.value = DevicesState(
                    isLoading = false,
                    failure = when {
                        signedOut -> SIGNED_OUT_MARKER
                        isUnidentified(error) -> UNIDENTIFIED_MARKER
                        else -> message(error)
                    },
                    needsSignIn = signedOut,
                )
            } finally {
                release(deployment)
            }
        }
    }

    fun isThisDevice(device: Device): Boolean {
        val uid = thisDeviceUID()
        return uid.isNotEmpty() && device.device_uid == uid
    }

    /** The picker follows the SERVER, never the tap */
    fun setAutoLogout(deployment: Deployment, months: Int) {
        _state.value = _state.value.copy(savingPolicy = true, policyError = null)
        scope.launch {
            try {
                val saved = operations(deployment).setSessionPolicy(months)
                _state.value = _state.value.copy(
                    autoLogoutMonths = saved.auto_logout_months,
                    savingPolicy = false,
                )
            } catch (error: Throwable) {
                _state.value = _state.value.copy(savingPolicy = false, policyError = message(error))
            } finally {
                release(deployment)
            }
        }
    }

    fun revoke(deployment: Deployment, device: Device) {
        _state.value = _state.value.copy(revoking = device.id, revokeError = null)
        scope.launch {
            try {
                operations(deployment).revoke(device.id)
                _state.value = _state.value.copy(
                    devices = _state.value.devices.filter { it.id != device.id },
                    revoking = null,
                )
            } catch (error: Throwable) {
                _state.value = _state.value.copy(revoking = null, revokeError = message(error))
            } finally {
                release(deployment)
            }
        }
    }

    fun signInAgain(deployment: Deployment, confirm: suspend () -> Boolean) {
        if (_state.value.signingIn) return
        _state.value = _state.value.copy(signingIn = true, signInError = null)
        job = scope.launch {
            try {
                if (!confirm()) return@launch
                enrol(deployment)
                val ops = operations(deployment)
                val listed = ops.listDevices().sortedBy { it.paired_at }
                val months = ops.sessionPolicy().auto_logout_months
                _state.value = DevicesState(devices = listed, isLoading = false, autoLogoutMonths = months)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                _state.value = _state.value.copy(signInError = message(error))
            } finally {
                _state.value = _state.value.copy(signingIn = false)
                release(deployment)
            }
        }
    }

    fun clearRevokeError() {
        _state.value = _state.value.copy(revokeError = null)
    }

    fun reset() {
        job?.cancel()
        job = null
        _state.value = DevicesState()
    }

    private fun message(error: Throwable): String =
        (error as? AgentError)?.message ?: error.message.orEmpty()

    companion object {
        /** The terms offered, in the order they read */
        val OFFERED_MONTHS = listOf(0, 1, 3, 6, 12)

        const val SIGNED_OUT_MARKER = "signed_out"

        const val UNIDENTIFIED_MARKER = "unidentified"

        /** The marker, not the wording */
        private val SESSION_MARKERS = listOf("session_expired", "device_not_paired")

        fun isSignedOut(error: Throwable): Boolean {
            val text = (error as? AgentError)?.message ?: error.message.orEmpty()
            return SESSION_MARKERS.any { text.contains(it) }
        }

        fun isUnidentified(error: Throwable): Boolean {
            val text = (error as? AgentError)?.message ?: error.message.orEmpty()
            return text.contains("device_unidentified")
        }
    }
}
