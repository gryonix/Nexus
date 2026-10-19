package com.skaymer.gryonixnexus.app.servers

import android.content.SharedPreferences
import com.skaymer.gryonixnexus.agentcontrol.AgentInstallContext
import com.skaymer.gryonixnexus.agentcontrol.ServiceMoveEndpoint
import com.skaymer.gryonixnexus.agentcontrol.ServiceMoveEvent
import com.skaymer.gryonixnexus.agentcontrol.ServiceMoveFailure
import com.skaymer.gryonixnexus.agentcontrol.ServiceMoveMachine
import com.skaymer.gryonixnexus.agentcontrol.ServiceMovePlan
import com.skaymer.gryonixnexus.agentcontrol.ServiceMoveRunner
import com.skaymer.gryonixnexus.agentcontrol.ServiceMoveUndo
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.ANSIStripper
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.MoveRouteResult
import com.skaymer.gryonixnexus.servercontrol.OutputTail
import com.skaymer.gryonixnexus.servercontrol.ServiceMovePolicy
import com.skaymer.gryonixnexus.servercontrol.ServiceMoveRecord
import com.skaymer.gryonixnexus.servercontrol.ServiceMoveRefusal
import com.skaymer.gryonixnexus.servercontrol.ServiceMoveRoute
import com.skaymer.gryonixnexus.servercontrol.ServiceMoveStep
import com.skaymer.gryonixnexus.servercontrol.placing
import com.skaymer.gryonixnexus.servercontrol.moveRoute
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json

class ServiceMoveRecords(private val prefs: SharedPreferences) {
    private fun key(deployment: String) = "service-move-$deployment"

    fun record(deployment: String): ServiceMoveRecord? =
        prefs.getString(key(deployment), null)?.let { runCatching { Json.decodeFromString(ServiceMoveRecord.serializer(), it) }.getOrNull() }

    fun save(record: ServiceMoveRecord) {
        prefs.edit().putString(key(record.deployment), Json.encodeToString(ServiceMoveRecord.serializer(), record)).apply()
    }

    fun clear(deployment: String) {
        prefs.edit().remove(key(deployment)).apply()
    }
}

/** A move waiting for the person's yes */
data class MoveAsk(val deployment: Deployment, val route: ServiceMoveRoute, val serviceName: String)

data class MoveRefused(val reason: ServiceMoveRefusal, val serviceName: String)

/** One move, while it runs and after it ends */
data class MoveRun(
    val serviceName: String,
    val targetName: String,
    val step: ServiceMoveStep = ServiceMoveStep.CHECK,
    val undoing: Boolean = false,
    val putBack: Boolean = false,
    val log: String = "",
    val isFinished: Boolean = false,
    val failure: ServiceMoveFailure? = null,
    val error: Throwable? = null,
    val undone: ServiceMoveUndo? = null,
) {
    val succeeded: Boolean get() = isFinished && failure == null && error == null && (undone?.problems.orEmpty().isEmpty())
}

class ServiceMoveViewModel(
    private val scope: CoroutineScope,
    private val machine: suspend (Deployment, DeploymentNode) -> ServiceMoveMachine,
    private val context: suspend (Deployment, ServiceMoveRoute) -> AgentInstallContext,
    private val persist: (Deployment) -> Unit,
    private val records: ServiceMoveRecords,
    private val release: suspend (Deployment) -> Unit = {},
) {
    private val _ask = MutableStateFlow<MoveAsk?>(null)
    val ask: StateFlow<MoveAsk?> = _ask.asStateFlow()

    private val _refused = MutableStateFlow<MoveRefused?>(null)
    val refused: StateFlow<MoveRefused?> = _refused.asStateFlow()

    private val _run = MutableStateFlow<MoveRun?>(null)
    val run: StateFlow<MoveRun?> = _run.asStateFlow()

    private val _interrupted = MutableStateFlow<ServiceMoveRecord?>(null)
    val interrupted: StateFlow<ServiceMoveRecord?> = _interrupted.asStateFlow()

    private val running = mutableSetOf<String>()
    private var closed = false

    fun isRunning(deployment: String): Boolean = deployment in running

    fun refreshInterrupted(deployment: String) {
        _interrupted.value = if (isRunning(deployment)) null else records.record(deployment)
    }

    fun request(deployment: Deployment, service: ServiceID, node: String) {
        val managed = ServiceRegistry.service(service) ?: return
        if (isRunning(deployment.id)) return
        if (!ServiceMovePolicy.isMovable(managed, deployment.serviceContext)) {
            _refused.value = MoveRefused(ServiceMoveRefusal.NOT_MOVABLE, managed.displayName)
            return
        }
        when (val result = deployment.moveRoute(service, node)) {
            is MoveRouteResult.Ready -> _ask.value = MoveAsk(deployment, result.route, managed.displayName)
            is MoveRouteResult.Refused -> _refused.value = MoveRefused(result.reason, managed.displayName)
        }
    }

    fun cancelAsk() {
        _ask.value = null
    }

    fun clearRefusal() {
        _refused.value = null
    }

    fun clearRun() {
        _run.value = null
    }

    fun confirm() {
        val ask = _ask.value ?: return
        _ask.value = null
        val record = ServiceMoveRecord(
            deployment = ask.deployment.id, service = ask.route.service.rawValue,
            source = ask.route.source.id, target = ask.route.target.id,
            transferID = UUID.randomUUID().toString().replace("-", "").lowercase(),
        )
        start(ask.deployment, ask.route, record, putBack = false)
    }

    /** Continues an interrupted move, or only puts everything back */
    fun resume(deployment: Deployment, putBack: Boolean) {
        val record = records.record(deployment.id) ?: return
        val service = ServiceID(record.service)
        val name = ServiceRegistry.service(service)?.displayName ?: record.service
        when (val result = deployment.moveRoute(service, record.target)) {
            is MoveRouteResult.Ready -> start(deployment, result.route, record, putBack)
            is MoveRouteResult.Refused -> _refused.value = MoveRefused(result.reason, name)
        }
    }

    private fun start(deployment: Deployment, route: ServiceMoveRoute, record: ServiceMoveRecord, putBack: Boolean) {
        val managed = ServiceRegistry.service(route.service) ?: return
        running += deployment.id
        closed = false
        _interrupted.value = null
        records.save(record)
        _run.value = MoveRun(managed.displayName, route.target.name.ifEmpty { route.target.endpoint.host }, record.step, putBack = putBack)
        scope.launch { drive(deployment, route, managed, record, putBack) }
    }

    private suspend fun drive(
        deployment: Deployment,
        route: ServiceMoveRoute,
        service: ManagedService,
        record: ServiceMoveRecord,
        putBack: Boolean,
    ) {
        try {
            val runner = runnerFor(deployment, route, service, record)
            if (putBack) finishUndo(deployment, runner.undo()) else {
                runner.run()
                succeed(deployment, route)
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: ServiceMoveFailure) {
            update { it.copy(isFinished = true, failure = failure) }
            if (failure.undone.problems.isEmpty()) records.clear(deployment.id)
        } catch (error: Exception) {
            update { it.copy(isFinished = true, error = error) }
            if (record.step == ServiceMoveStep.CHECK) records.clear(deployment.id)
        } finally {
            closed = true
            running -= deployment.id
            refreshInterrupted(deployment.id)
            release(deployment)
        }
    }

    private suspend fun runnerFor(
        deployment: Deployment,
        route: ServiceMoveRoute,
        service: ManagedService,
        record: ServiceMoveRecord,
    ): ServiceMoveRunner {
        val ingress = service.webIngress(deployment.serviceContext) ?: throw ServiceMoveRefusalException(ServiceMoveRefusal.NOT_MOVABLE)
        val port = if (route.target.legacySlot == null) route.target.endpoint.port else deployment.entry.port
        val plan = ServiceMovePlan(
            service = route.service,
            target = ServiceMoveEndpoint(route.target.endpoint.host, port, deployment.entry.user),
            sourceEntryAddress = route.sourceEntryAddress,
            targetEntryAddress = route.targetEntryAddress,
            localPort = ingress.upstreamPort,
            localHTTPS = ingress.upstreamHTTPS,
            overwriteForwardedFor = ingress.overwriteForwardedFor,
            installContext = context(deployment, route),
        )
        return ServiceMoveRunner(
            plan, record,
            machine(deployment, route.source), machine(deployment, route.target), machine(deployment, route.front),
            onRecord = { saved -> if (!closed) records.save(saved) },
            onEvent = ::heard,
        )
    }

    private fun heard(event: ServiceMoveEvent) = when (event) {
        is ServiceMoveEvent.Step -> update { it.copy(step = event.step) }
        is ServiceMoveEvent.Log -> update { it.copy(log = tail(it.log + lineOf(event.text))) }
        ServiceMoveEvent.Undoing -> update { it.copy(undoing = true) }
    }

    private fun succeed(deployment: Deployment, route: ServiceMoveRoute) {
        closed = true
        records.clear(deployment.id)
        persist(deployment.placing(route.service, route.target.id))
        update { it.copy(isFinished = true) }
    }

    private fun finishUndo(deployment: Deployment, undone: ServiceMoveUndo) {
        closed = true
        if (undone.problems.isEmpty()) records.clear(deployment.id)
        update { it.copy(isFinished = true, undone = undone) }
    }

    private fun update(change: (MoveRun) -> MoveRun) {
        _run.value = _run.value?.let(change)
    }

    private fun lineOf(text: String) = if (text.endsWith("\n")) text else text + "\n"

    private fun tail(text: String) = OutputTail.tail(ANSIStripper.strip(text))
}

class ServiceMoveRefusalException(val reason: ServiceMoveRefusal) : Exception(reason.name)
