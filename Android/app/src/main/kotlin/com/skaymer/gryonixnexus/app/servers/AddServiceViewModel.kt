package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationKind
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.catalog.ForwardedPorts
import com.skaymer.gryonixnexus.catalog.ServiceDataPlacement
import com.skaymer.gryonixnexus.catalog.ServiceDefaultHostnames
import com.skaymer.gryonixnexus.agentcontrol.AgentInstallContext
import com.skaymer.gryonixnexus.agentcontrol.AgentPlanPurpose
import com.skaymer.gryonixnexus.agentcontrol.AgentInstallSettings
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceCategory
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.ANSIStripper
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.OutputTail
import com.skaymer.gryonixnexus.servercontrol.servicesBehindRelay
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class AddServiceRun(
    val queue: List<ServiceID>,
    val current: ServiceID?,
    val installed: List<ServiceID> = emptyList(),
    val log: String = "",
    val isFinished: Boolean = false,
    val errorMessage: String? = null,
)

data class AddServiceState(val run: AddServiceRun? = null)

/** Adding a service to a server that already runs */
class AddServiceViewModel(
    private val scope: CoroutineScope,
    private val installs: suspend (Deployment, ServiceID, AgentInstallContext, (String) -> Unit) -> Unit,
    /** The install context for one service on its machine */
    private val contexts: suspend (Deployment, ServiceID) -> AgentInstallContext,
    private val installedOnHost: suspend (Deployment) -> Set<ServiceID> = { it.services },
    private val persist: (Deployment) -> Unit = {},
    private val release: suspend (Deployment) -> Unit = {},
    /** Installs the agent on a server that has none */
    private val installAgent: suspend (Deployment, (String) -> Unit) -> Deployment = { it, _ -> it },
    /** DNS names and relay forwards for a newly added service */
    private val afterInstall: suspend (Deployment, ManagedService, Boolean) -> List<String> = { _, _, _ -> emptyList() },
    /** Settings a service needs minted just before it installs */
    private val beforeInstall: suspend (Deployment, ManagedService) -> Map<String, String> = { _, _ -> emptyMap() },
    /** The whole list to the agent; what it installed */
    private val plans: (suspend (Deployment, List<Pair<ServiceID, AgentInstallContext>>, AgentPlanPurpose, (String) -> Unit, (String) -> Unit) -> Set<ServiceID>)? = null,
) {
    private val _state = MutableStateFlow(AddServiceState())
    val state: StateFlow<AddServiceState> = _state.asStateFlow()

    /** Installs the services; with a mount, their data goes there */
    fun install(deployment: Deployment, services: List<ManagedService>, dataMount: String? = null) {
        run(deployment, services, dataMount, AgentPlanPurpose.ADD)
    }

    /** Every installed service again, as repair and reinstall do */
    fun rerun(deployment: Deployment, repair: Boolean = true) {
        val purpose = if (repair) AgentPlanPurpose.REPAIR else AgentPlanPurpose.REINSTALL
        run(deployment, ServiceRegistry.services(deployment.services), null, purpose)
    }

    private fun run(deployment: Deployment, services: List<ManagedService>, dataMount: String?, purpose: AgentPlanPurpose) {
        if (services.isEmpty()) return
        val rerun = purpose != AgentPlanPurpose.ADD
        scope.launch {
            _state.value = AddServiceState(
                AddServiceRun(queue = services.map { it.id }, current = services.first().id),
            )
            val notice = when (purpose) {
                AgentPlanPurpose.REPAIR -> OperationNotices.start(
                    R.string.notice_repairing, deployment.name, server = deployment.name, kind = OperationKind.INSTALL,
                )
                AgentPlanPurpose.REINSTALL -> OperationNotices.start(
                    R.string.notice_reinstalling, deployment.name, server = deployment.name, kind = OperationKind.INSTALL,
                )
                else -> OperationNotices.start(
                    R.string.notice_installing, services.joinToString(", ") { it.displayName },
                    server = deployment.name, kind = OperationKind.INSTALL,
                )
            }
            var record = deployment
            if (dataMount != null) {
                val placed = services.fold(record.serviceSettings) { settings, service ->
                    ServiceDataPlacement.place(settings, service.id, dataMount)
                }
                record = record.copy(serviceSettings = placed)
                persist(record)
            }
            try {
                if (!record.usesAgent) {
                    record = installAgent(record) { chunk -> append(chunk) }.copy(usesAgent = true)
                    persist(record)
                }
                val steps = if (rerun) ServiceInstallPlan.rerun(services) else ServiceInstallPlan.steps(services, record.services)
                val prepared = prepare(record, steps)
                val runPlan = plans
                if (runPlan != null) {
                    val requests = prepared.map { (step, _, context) -> step.service.id to context }
                    val done = runPlan(record, requests, purpose, { id ->
                        ServiceRegistry.service(ServiceID(id))?.let { notice.update(it.displayName) }
                    }) { chunk -> append(chunk) }
                    for ((step, planned, _) in prepared) {
                        if (step.service.id !in done) continue
                        record = settle(record, planned, step, rerun && step == steps.last())
                    }
                    val missed = steps.filter { it.service.id !in done }
                    if (missed.isNotEmpty()) {
                        error(OperationNotices.text(R.string.install_not_installed, missed.joinToString(", ") { it.service.displayName }))
                    }
                } else {
                    for ((step, planned, context) in prepared) {
                        _state.value = AddServiceState(_state.value.run!!.copy(current = step.service.id))
                        notice.update(step.service.displayName)
                        installs(record, step.service.id, context) { chunk -> append(chunk) }
                        record = settle(record, planned, step, rerun && step == steps.last())
                    }
                }
                finish { it.copy(isFinished = true, current = null) }
                notice.finish(OperationNotices.text(R.string.notice_done))
            } catch (cancelled: CancellationException) {
                notice.finish(OperationNotices.text(R.string.notice_continues))
                throw cancelled
            } catch (failure: Exception) {
                release(record)
                val message = failure.message ?: failure::class.simpleName
                finish { it.copy(isFinished = true, current = null, errorMessage = message) }
                notice.finish("", message)
            }
        }
    }

    private data class Prepared(val step: ServiceInstallPlan.Step, val planned: Deployment, val context: AgentInstallContext)

    /** Each step's request, hostnames pinned one after another */
    private suspend fun prepare(start: Deployment, steps: List<ServiceInstallPlan.Step>): List<Prepared> {
        var record = start
        val hostServices = installedOnHost(start)
        return steps.map { step ->
            val service = step.service
            val onHost = hostServices + record.services + step.alsoProtocols
            val planned = record.copy(
                services = record.services + installedServices(service) + step.alsoProtocols,
                serviceSettings = ServiceDefaultHostnames.pinningSiblings(
                    service.id, record.serviceSettings, record.services, record.domain,
                ),
            )
            var context = contexts(planned, service.id)
            AgentInstallSettings.vpnProtocolList(service.id, onHost)?.let { protocols ->
                context = context.copy(settings = context.settings + (AgentInstallSettings.VPN_PROTOCOLS_KEY to protocols))
            }
            context = context.copy(settings = context.settings + beforeInstall(planned, service))
            record = planned
            Prepared(step, planned, context)
        }
    }

    /** Records one installed step, then DNS and relay */
    private suspend fun settle(record: Deployment, planned: Deployment, step: ServiceInstallPlan.Step, forcePorts: Boolean): Deployment {
        val next = record.copy(services = record.services + planned.services, serviceSettings = planned.serviceSettings)
        val portsChanged = forcePorts || forwardedPorts(record) != forwardedPorts(next)
        persist(next)
        afterInstall(next, step.service, portsChanged).forEach { note -> append("\n$note\n") }
        _state.value = AddServiceState(
            _state.value.run!!.copy(installed = _state.value.run!!.installed + step.service.id + step.alsoProtocols),
        )
        return next
    }

    /** Runs an installed service's install again with new settings */
    fun reapply(
        deployment: Deployment,
        service: ManagedService,
        once: Map<String, String> = emptyMap(),
        afterwards: suspend () -> Unit = {},
    ) {
        scope.launch {
            _state.value = AddServiceState(AddServiceRun(queue = listOf(service.id), current = service.id))
            val notice = OperationNotices.start(
                R.string.notice_installing, service.displayName, server = deployment.name, kind = OperationKind.INSTALL,
            )
            try {
                val context = contexts(deployment, service.id).let { it.copy(settings = it.settings + once) }
                installs(deployment, service.id, context) { chunk -> append(chunk) }
                persist(deployment)
                afterwards()
                finish { it.copy(isFinished = true, current = null, installed = listOf(service.id)) }
                notice.finish(OperationNotices.text(R.string.notice_done))
            } catch (cancelled: CancellationException) {
                notice.finish(OperationNotices.text(R.string.notice_continues))
                throw cancelled
            } catch (failure: Exception) {
                val message = failure.message ?: failure::class.simpleName
                finish { it.copy(isFinished = true, current = null, errorMessage = message) }
                notice.finish("", message)
            }
        }
    }

    /** Points Reality at another camouflage site; keys and devices stay */
    fun changeRealitySite(deployment: Deployment, site: String) {
        val service = ServiceRegistry.service(ServiceID.XRAY_REALITY) ?: return
        val settings = deployment.serviceSettings.copy(xrayRealitySNI = site)
        reapply(deployment.copy(serviceSettings = settings), service)
    }

    /** Gives Reality a new key pair; devices keep their ids */
    fun renewRealityKey(deployment: Deployment, afterwards: suspend () -> Unit = {}) {
        val service = ServiceRegistry.service(ServiceID.XRAY_REALITY) ?: return
        val once = mapOf(AgentInstallSettings.XRAY_REALITY_NEW_KEY_KEY to java.util.UUID.randomUUID().toString())
        reapply(deployment, service, once, afterwards)
    }

    fun clear() {
        _state.value = AddServiceState()
    }

    private fun append(chunk: String) {
        val run = _state.value.run ?: return
        _state.value = AddServiceState(
            run.copy(log = OutputTail.tail(WrapperLogText.readable(ANSIStripper.strip(run.log + chunk)))),
        )
    }

    private fun finish(change: (AddServiceRun) -> AddServiceRun) {
        val run = _state.value.run ?: return
        _state.value = AddServiceState(change(run))
    }

    companion object {
        /** Whether this server can be added to at all */
        fun canAdd(deployment: Deployment, agentTransportAvailable: Boolean = true): Boolean =
            agentTransportAvailable

        /** The ports a relay forwards for this deployment */
        fun forwardedPorts(deployment: Deployment): List<Int> {
            val services = deployment.servicesBehindRelay
            val context = deployment.serviceContext
            return ForwardedPorts.tcp(services, context) + ForwardedPorts.udp(services, context).map { -it }
        }

        /** What a single pick actually installs */
        fun installedServices(service: ManagedService): Set<ServiceID> =
            if (service.id in ServiceID.VPN_PROTOCOLS) {
                setOf(service.id, ServiceID.VPN_PANEL)
            } else {
                setOf(service.id)
            }

        /** Whether this server can still take this service */
        fun offerable(
            service: ManagedService,
            installed: Set<ServiceID>,
            localOnly: Boolean,
            /** Whether this device holds an account-scoped Cloudflare token */
            canIssueTunnelToken: Boolean = false,
            /** What is ticked in the sheet right now */
            selected: Set<ServiceID> = emptySet(),
        ): Boolean {
            if (service.category == ServiceCategory.IMPLICIT) return false
            if (service.id in installed) return false
            if (installed.any { it in service.conflicts }) return false
            if (service.id == ServiceID.CLOUDFLARED && !canIssueTunnelToken) return false
            if (!hasItsHub(service, installed, selected)) return false
            if (localOnly) {
                if (service.category == ServiceCategory.MAIL) return false
                if (service.category == ServiceCategory.VPN) return false
            }
            return true
        }

        /** What is still on offer, by shelf, in catalog order */
        fun available(
            installed: Set<ServiceID>,
            localOnly: Boolean,
            canIssueTunnelToken: Boolean = false,
            selected: Set<ServiceID> = emptySet(),
        ): List<Pair<ServiceCategory, List<ManagedService>>> {
            val buckets = LinkedHashMap<ServiceCategory, MutableList<ManagedService>>()
            ServiceRegistry.all
                .filter { offerable(it, installed, localOnly, canIssueTunnelToken, selected) }
                .forEach { buckets.getOrPut(it.category) { mutableListOf() }.add(it) }
            return buckets.entries.sortedBy { it.key }.map { it.key to it.value }
        }

        fun toggle(
            selection: Set<ServiceID>,
            service: ManagedService,
            installed: Set<ServiceID> = emptySet(),
        ): Set<ServiceID> {
            if (service.id in selection) {
                val left = selection - service.id
                return if (ServiceID.HOME_ASSISTANT in installed || ServiceID.HOME_ASSISTANT in left) {
                    left
                } else {
                    left - ServiceID.SMART_HOME_ADD_ONS
                }
            }
            return selection.filterTo(mutableSetOf()) { it !in service.conflicts } + service.id
        }

        /** An add-on is offered only where its hub is */
        private fun hasItsHub(
            service: ManagedService?,
            installed: Set<ServiceID>,
            selected: Set<ServiceID>,
        ): Boolean {
            if (service != null && service.id !in ServiceID.SMART_HOME_ADD_ONS) return true
            return ServiceID.HOME_ASSISTANT in installed || ServiceID.HOME_ASSISTANT in selected
        }

        fun chosen(selection: Set<ServiceID>): List<ManagedService> =
            ServiceRegistry.all.filter { it.id in selection }
    }
}
