package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationNotice
import com.skaymer.gryonixnexus.app.notify.OperationKind
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.ANSIStripper
import com.skaymer.gryonixnexus.servercontrol.AdminLockdownState
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.OutputTail
import com.skaymer.gryonixnexus.servercontrol.PurgeOptions
import com.skaymer.gryonixnexus.servercontrol.RemovalScope
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import com.skaymer.gryonixnexus.servercontrol.ServiceRemovalManaging
import com.skaymer.gryonixnexus.servercontrol.ServiceRemovalRouting
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** One removal, while it runs and after it ends */
data class RemovalRun(
    val service: ServiceID,
    val log: String = "",
    val isFinished: Boolean = false,
    val errorMessage: String? = null,
    val note: String? = null,
    val purge: PurgeOptions = PurgeOptions.NONE,
) {
    val succeeded: Boolean get() = isFinished && errorMessage == null
}

data class ServiceRemovalState(val run: RemovalRun? = null)

/** What removing this service is about to delete for good */
enum class PurgeWarning {
    /** Containers and configuration only: data and backups stay on disk */
    NOTHING,
    DATA,
    BACKUPS,
    EVERYTHING,
}

/** Taking ONE service off a server */
class ServiceRemovalViewModel(
    private val scope: CoroutineScope,
    private val removals: suspend (Deployment, ManagedService) -> ServiceRemovalManaging,
    /** Redraws the host's wrappers and sudoers after an agent removal */
    private val refreshHostSurface: suspend (Deployment) -> Unit = {},
    private val persist: (Deployment) -> Unit = {},
    private val release: suspend (Deployment) -> Unit = {},
    private val agentTransportAvailable: Boolean = true,
    /** Takes a removed service's DNS names down; returns notes */
    private val unpublish: suspend (Deployment, ManagedService, Deployment) -> List<String> = { _, _, _ -> emptyList() },
    /** Reinstalls the VPN through the agent with these protocols only */
    private val keepVPNProtocols: suspend (Deployment, Set<ServiceID>, (String) -> Unit) -> Unit = { _, _, _ -> },
) {
    private val _state = MutableStateFlow(ServiceRemovalState())
    val state: StateFlow<ServiceRemovalState> = _state.asStateFlow()

    fun route(deployment: Deployment): ServiceControlRoute =
        ServiceRemovalRouting.route(
            scope = RemovalScope.SERVICE,
            usesAgent = deployment.usesAgent,
            agentTransportAvailable = agentTransportAvailable,
        )

    fun remove(deployment: Deployment, service: ManagedService, purge: PurgeOptions) {
        scope.launch {
            _state.value = ServiceRemovalState(RemovalRun(service = service.id, purge = purge))
            val notice = OperationNotices.start(
                R.string.notice_removing, service.displayName, server = deployment.name, kind = OperationKind.REMOVAL,
            )
            runNotice = notice
            notice.stopsAgentJobs(deployment)
            try {
                val left = remainingVPNProtocols(service, deployment.services)
                if (left.isEmpty()) {
                    val log = removals(deployment, service).remove(service, purge) { chunk -> append(chunk) }
                    finish { it.copy(isFinished = true, log = readable(log)) }
                } else {
                    keepVPNProtocols(deployment, left) { chunk -> append(chunk) }
                    finish { it.copy(isFinished = true) }
                }
                val remaining = deployment.copy(
                    services = deployment.services - removedServices(service, deployment.services),
                )
                persist(remaining)
                unpublish(deployment, service, remaining).forEach { note -> append("\n$note\n") }
                if (route(deployment) == ServiceControlRoute.AGENT) {
                    noteHostSurface(remaining)
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                finish {
                    it.copy(isFinished = true, errorMessage = failure.message ?: failure::class.simpleName)
                }
            }
            runNotice = null
            notice.finish(OperationNotices.text(R.string.notice_done), _state.value.run?.errorMessage)
        }
    }

    private var runNotice: OperationNotice? = null

    /** Dismisses a finished run's log */
    fun clear() {
        _state.value = ServiceRemovalState()
    }

    private suspend fun noteHostSurface(deployment: Deployment) {
        try {
            refreshHostSurface(deployment)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            finish { it.copy(note = failure.message ?: failure::class.simpleName) }
        }
    }

    private fun append(chunk: String) {
        runNotice?.update(OperationNotices.lastLine(chunk))
        val run = _state.value.run ?: return
        _state.value = ServiceRemovalState(run.copy(log = readable(run.log + chunk)))
    }

    private fun finish(change: (RemovalRun) -> RemovalRun) {
        val run = _state.value.run ?: return
        _state.value = ServiceRemovalState(change(run))
    }

    private fun readable(text: String): String =
        OutputTail.tail(WrapperLogText.readable(ANSIStripper.strip(text)))

    companion object {
        /** Which sentence the sheet prints about what disappears */
        fun warning(purge: PurgeOptions): PurgeWarning = when {
            purge.data && purge.backups -> PurgeWarning.EVERYTHING
            purge.data -> PurgeWarning.DATA
            purge.backups -> PurgeWarning.BACKUPS
            else -> PurgeWarning.NOTHING
        }

        /** VPN protocols that stay after this one goes */
        fun remainingVPNProtocols(service: ManagedService, installed: Set<ServiceID>): Set<ServiceID> =
            if (service.id in ServiceID.VPN_PROTOCOLS) installed.intersect(ServiceID.VPN_PROTOCOLS) - service.id
            else emptySet()

        /** What a single removal actually takes down */
        fun removedServices(service: ManagedService, installed: Set<ServiceID> = emptySet()): Set<ServiceID> =
            when {
                remainingVPNProtocols(service, installed).isNotEmpty() -> setOf(service.id)
                service.id in ServiceID.VPN_PROTOCOLS || service.id == ServiceID.VPN_PANEL ->
                    ServiceID.VPN_PROTOCOLS + ServiceID.VPN_PANEL
                else -> setOf(service.id)
            }

        fun alsoRemovedNames(service: ManagedService, installed: Set<ServiceID> = emptySet()): List<String> {
            val removed = removedServices(service, installed)
            if (removed.size <= 1) return emptyList()
            return (removed - service.id).mapNotNull { ServiceRegistry.service(it)?.displayName }.sorted()
        }

        fun unguardedPanelNames(
            service: ManagedService,
            lockdown: AdminLockdownState?,
            pages: List<LockdownPage>,
            installed: Set<ServiceID> = emptySet(),
        ): List<String> {
            val removed = removedServices(service, installed)
            if (ServiceID.VPN_PANEL !in removed) return emptyList()
            if (lockdown == null) return emptyList()
            return pages.filter { it.id !in removed && lockdown.guards(it.host) }.map { it.name }
        }
    }
}
