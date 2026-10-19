package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.AdminLockdownManaging
import com.skaymer.gryonixnexus.servercontrol.AdminLockdownState
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.StatusOperations
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class HostAction { RESTART_SSHD, REBOOT, POWER_OFF }

data class HostActionOutcome(
    val action: HostAction,
    val host: SSHHostID? = null,
    val errorMessage: String? = null,
) {
    val isError: Boolean get() = errorMessage != null
}

/** What the admin-guard row can say */
sealed class LockdownRead {
    data object Idle : LockdownRead()
    data object Loading : LockdownRead()
    data class Loaded(val state: AdminLockdownState) : LockdownRead()
    data class Failed(val message: String) : LockdownRead()

    val value: AdminLockdownState? get() = (this as? Loaded)?.state
}

data class LockdownPage(val id: ServiceID, val name: String, val host: String)

/** What to send the wrapper for a per-page change */
sealed class LockdownRequest {
    data object All : LockdownRequest()

    /** The explicit host list */
    data class Only(val hosts: List<String>) : LockdownRequest()
}

data class HostActionsState(
    val running: HostAction? = null,
    val outcome: HostActionOutcome? = null,
    val lockdown: LockdownRead = LockdownRead.Idle,
)

class HostActionsViewModel(
    private val scope: CoroutineScope,
    private val runners: suspend (Deployment) -> SSHCommandRunner,
    /** Which implementation drives `/opt/gryonixnexus-admin-lockdown.sh` */
    private val lockdowns: suspend (Deployment) -> AdminLockdownManaging,
    private val release: suspend (Deployment) -> Unit = {},
) {
    private val _state = MutableStateFlow(HostActionsState())
    val state: StateFlow<HostActionsState> = _state.asStateFlow()

    /** Restarts sshd on every machine of this server */
    fun restartSSHD(deployment: Deployment) {
        start(HostAction.RESTART_SSHD) {
            val operations = StatusOperations(runners(deployment), deployment.dashboardConfig)
            for (node in order(deployment)) {
                try {
                    operations.restartSSHD(node.sshHost)
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (failure: Exception) {
                    release(deployment)
                    return@start HostActionOutcome(
                        HostAction.RESTART_SSHD, node.sshHost, reason(failure),
                    )
                }
            }
            HostActionOutcome(HostAction.RESTART_SSHD)
        }
    }

    /** Reboots one machine */
    fun reboot(deployment: Deployment, host: SSHHostID) {
        start(HostAction.REBOOT) {
            try {
                StatusOperations(runners(deployment), deployment.dashboardConfig).reboot(host)
                HostActionOutcome(HostAction.REBOOT, host)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                HostActionOutcome(HostAction.REBOOT, host, reason(failure))
            } finally {
                release(deployment)
            }
        }
    }

    /** Shuts down the machine Wake on LAN brings back */
    fun powerOff(deployment: Deployment) {
        val host = WakeOnLANViewModel.homeMachine(deployment)?.sshHost ?: return
        start(HostAction.POWER_OFF) {
            try {
                StatusOperations(runners(deployment), deployment.dashboardConfig).powerOff(host)
                HostActionOutcome(HostAction.POWER_OFF, host)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                HostActionOutcome(HostAction.POWER_OFF, host, reason(failure))
            } finally {
                release(deployment)
            }
        }
    }

    fun clearOutcome() {
        _state.value = _state.value.copy(outcome = null)
    }

    fun reset() {
        _state.value = HostActionsState()
    }

    // ------------------------------------------------------- Admin lockdown

    fun refreshLockdown(deployment: Deployment) {
        readLockdown(deployment) { it.status() }
    }

    fun setLockdown(deployment: Deployment, enabled: Boolean) {
        readLockdown(deployment) { it.set(enabled) }
    }

    /** Turns ONE page's guard on or off */
    fun setLockdown(deployment: Deployment, host: String, guarded: Boolean) {
        val current = _state.value.lockdown.value ?: return
        val request = request(deployment, current, host, guarded)
        readLockdown(deployment) { operations ->
            when (request) {
                is LockdownRequest.All -> operations.set(true)
                is LockdownRequest.Only -> operations.set(request.hosts)
            }
        }
    }

    private fun readLockdown(
        deployment: Deployment,
        probe: suspend (AdminLockdownManaging) -> AdminLockdownState,
    ) {
        scope.launch {
            _state.value = _state.value.copy(lockdown = LockdownRead.Loading)
            _state.value = _state.value.copy(
                lockdown = try {
                    LockdownRead.Loaded(probe(lockdowns(deployment)))
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (failure: Exception) {
                    release(deployment)
                    LockdownRead.Failed(reason(failure))
                },
            )
        }
    }

    private fun start(action: HostAction, body: suspend () -> HostActionOutcome) {
        if (_state.value.running != null) return
        _state.value = _state.value.copy(running = action, outcome = null)
        scope.launch {
            val outcome = body()
            _state.value = _state.value.copy(running = null, outcome = outcome)
        }
    }

    private fun reason(failure: Exception): String =
        failure.message ?: failure::class.simpleName.orEmpty()

    companion object {
        /** Whether this server has the guard at all */
        fun hasAdminLockdown(deployment: Deployment): Boolean =
            ServiceID.VPN_PANEL in deployment.services

        fun lockdownPages(deployment: Deployment): List<LockdownPage> {
            val context = deployment.serviceContext
            return ServiceRegistry.services(deployment.services).mapNotNull { service ->
                service.webIngress(context)?.let {
                    LockdownPage(service.id, service.displayName, it.hostname)
                }
            }
        }

        fun order(deployment: Deployment): List<DeploymentNode> = deployment.teardownOrder

        /** What flipping one page means for the WHOLE guard */
        fun request(
            deployment: Deployment,
            current: AdminLockdownState,
            host: String,
            guarded: Boolean,
        ): LockdownRequest {
            val all = lockdownPages(deployment).map { it.host }.toSet()
            val wanted = all.filter { current.guards(it) }.toMutableSet()
            if (guarded) wanted.add(host) else wanted.remove(host)
            if (wanted == all && all.isNotEmpty()) return LockdownRequest.All
            val context = deployment.serviceContext
            val expanded = wanted.flatMap { listOf(it) + context.mirroredHostnames(it) }
            return LockdownRequest.Only(expanded.sorted())
        }
    }
}
