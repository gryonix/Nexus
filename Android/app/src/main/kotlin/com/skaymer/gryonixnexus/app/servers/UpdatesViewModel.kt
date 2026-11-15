package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.app.widgets.WidgetFeed

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationNotice
import com.skaymer.gryonixnexus.app.notify.OperationKind
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.ServiceUpdateStatus
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.servercontrol.ANSIStripper
import com.skaymer.gryonixnexus.servercontrol.AutoUpdateSettings
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.OutputTail
import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateManaging
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateRouting
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateRunLog
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateRunRecord
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class UpdateRun(
    val service: ServiceID,
    val log: String = "",
    val isFinished: Boolean = false,
    val outcome: ServiceUpdateRunRecord.Outcome? = null,
    val errorMessage: String? = null,
    val continuesOnServer: Boolean = false,
)

/** Everything the updates screen draws about one server */
data class UpdatesState(
    /** What the last check said about each service */
    val reports: Map<ServiceID, ServiceUpdateStatus> = emptyMap(),
    val checking: Boolean = false,
    val schedule: AutoUpdateSettings = AutoUpdateSettings(),
    val runLog: ServiceUpdateRunLog = ServiceUpdateRunLog(lastRun = null, records = emptyList()),
    /** Whether the SERVER has answered about its schedule */
    val hasLoadedSchedule: Boolean = false,
    val errorMessage: String? = null,
    val isSaving: Boolean = false,
    val run: UpdateRun? = null,
)

class UpdatesViewModel(
    private val scope: CoroutineScope,
    /** How updates are driven for a deployment */
    private val updates: suspend (Deployment) -> ServiceUpdateManaging,
    private val release: suspend (Deployment) -> Unit = {},
    private val agentTransportAvailable: Boolean = false,
    /** Lets the strip pick up a run the stream lost */
    private val onLostConnection: (Deployment) -> Unit = {},
) {
    private val _state = MutableStateFlow(UpdatesState())
    val state: StateFlow<UpdatesState> = _state.asStateFlow()

    private var job: Job? = null

    fun route(deployment: Deployment): ServiceControlRoute =
        ServiceUpdateRouting.route(
            usesAgent = deployment.usesAgent,
            agentTransportAvailable = agentTransportAvailable,
        )

    /** Reads the stored schedule and the last run's record */
    fun load(deployment: Deployment) {
        scope.launch {
            try {
                val schedule = updates(deployment).loadSchedule()
                _state.update { it.copy(
                    schedule = schedule,
                    hasLoadedSchedule = true,
                    errorMessage = null,
                ) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                _state.update { it.copy(errorMessage = reason(failure)) }
            }
            loadRunLog(deployment)
        }
    }

    /** Asks the server what has moved */
    fun check(deployment: Deployment) {
        job?.cancel()
        job = scope.launch {
            _state.update { it.copy(checking = true) }
            try {
                val reported = updates(deployment).check()
                val answers = reported.associate { it.service to it.status }.toMutableMap()
                for (id in deployment.services) {
                    if (answers[id] != null) continue
                    val service = ServiceRegistry.service(id) ?: continue
                    answers[id] = statusForUnreported(service, deployment.serviceContext)
                }
                _state.update { it.copy(
                    reports = answers,
                    checking = false,
                    errorMessage = null,
                ) }
                WidgetFeed.updates(deployment, answers.values.count { it is ServiceUpdateStatus.Available }, answers.size)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                _state.update { it.copy(
                    reports = emptyMap(),
                    checking = false,
                    errorMessage = reason(failure),
                ) }
            }
        }
    }

    fun run(deployment: Deployment, service: ServiceID) {
        scope.launch {
            _state.update { it.copy(run = UpdateRun(service = service)) }
            val name = ServiceRegistry.service(service)?.displayName ?: service.rawValue
            val notice = OperationNotices.start(
                R.string.updates_updating, name, server = deployment.name, kind = OperationKind.UPDATE,
            )
            runNotice = notice
            notice.stopsAgentJobs(deployment)
            try {
                val record = updates(deployment).run(service) { chunk -> append(chunk) }
                finish { it.copy(isFinished = true, outcome = record.outcome) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                if (deployment.usesAgent && isLostConnection(failure)) {
                    finish { it.copy(isFinished = true, continuesOnServer = true) }
                    onLostConnection(deployment)
                } else {
                    finish { it.copy(isFinished = true, errorMessage = reason(failure)) }
                }
            }
            _state.value.run?.let { run ->
                val text = OperationNotices.text(
                    if (run.continuesOnServer) R.string.notice_continues else R.string.notice_done,
                )
                notice.finish(text, run.errorMessage, retry = { run(deployment, service) })
            }
            runNotice = null
            _state.update { it.copy(reports = it.reports - service) }
            loadRunLog(deployment)
        }
    }

    private var runNotice: OperationNotice? = null

    /** Dismisses a finished run's log */
    fun clearRun() {
        _state.update { it.copy(run = null) }
    }

    /** Writes a new schedule to the server */
    fun save(deployment: Deployment, settings: AutoUpdateSettings) {
        scope.launch {
            _state.update { it.copy(isSaving = true) }
            try {
                updates(deployment).save(settings)
                _state.update { it.copy(
                    schedule = settings,
                    hasLoadedSchedule = true,
                    isSaving = false,
                    errorMessage = null,
                ) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                _state.update { it.copy(isSaving = false, errorMessage = reason(failure)) }
            }
        }
    }

    fun reset() {
        job?.cancel()
        job = null
        _state.value = UpdatesState()
    }

    private suspend fun loadRunLog(deployment: Deployment) {
        try {
            val log = updates(deployment).loadStatus()
            _state.update { it.copy(runLog = log) }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            // Deliberately silent — see [load].
        }
    }

    private fun append(chunk: String) {
        runNotice?.update(OperationNotices.lastLine(chunk))
        _state.update { current ->
            val run = current.run ?: return@update current
            current.copy(run = run.copy(log = OutputTail.tail(WrapperLogText.readable(ANSIStripper.strip(run.log + chunk)))))
        }
    }

    private fun finish(change: (UpdateRun) -> UpdateRun) {
        _state.update { current -> current.run?.let { current.copy(run = change(it)) } ?: current }
    }

    /** Anything but a reply the agent itself sent */
    private fun isLostConnection(failure: Exception): Boolean =
        failure !is AgentError.Rpc && failure !is ServerControlError.CommandFailed

    private fun reason(failure: Exception): String =
        failure.message ?: failure::class.simpleName.orEmpty()

    companion object {
        /** What a service the check did not mention should show */
        fun statusForUnreported(
            service: ManagedService,
            context: ServiceContext,
        ): ServiceUpdateStatus = when (service.updateSpec(context).flavour) {
            UpdateSpec.Flavour.OWN_UPDATER -> ServiceUpdateStatus.SelfManaged
            UpdateSpec.Flavour.BUILT_ON_SERVER -> ServiceUpdateStatus.RebuiltBySetup
            UpdateSpec.Flavour.COMPOSE_PULL -> ServiceUpdateStatus.Unknown
        }

        fun rows(
            deployment: Deployment,
            reports: Map<ServiceID, ServiceUpdateStatus>,
        ): List<ServiceID> {
            val own = updatableServices(deployment).map { it.id }
            // Report order is the wrapper's, which is the catalog's.
            return own + reports.keys.filter { it !in deployment.services }
        }

        fun updatableServices(deployment: Deployment): List<ManagedService> =
            deployment.services.mapNotNull { ServiceRegistry.service(it) }
                .filter {
                    it.updateSpec(deployment.serviceContext).flavour !=
                        UpdateSpec.Flavour.BUILT_ON_SERVER
                }
    }
}
