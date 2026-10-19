package com.skaymer.gryonixnexus.app.containers

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationNotice
import com.skaymer.gryonixnexus.app.notify.OperationKind
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.agentcontrol.ContainerAction
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupCadence
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupPlan
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupRunEvent
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupListing
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupSchedule
import com.skaymer.gryonixnexus.agentcontrol.ContainerDetail
import com.skaymer.gryonixnexus.agentcontrol.ContainerInventory
import com.skaymer.gryonixnexus.agentcontrol.ContainerLogLine
import com.skaymer.gryonixnexus.agentcontrol.ContainerRemovalEvent
import com.skaymer.gryonixnexus.agentcontrol.ContainerRemovalPreview
import com.skaymer.gryonixnexus.agentcontrol.ContainerUpdateEvent
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch

/** One server's answer about what it is running */
sealed class ServerContainers {
    object Loading : ServerContainers()

    /** The host answered */
    data class Loaded(val inventory: ContainerInventory) : ServerContainers()

    data class Failed(val message: String) : ServerContainers()

    /** The server has no agent, so nothing can ask it */
    object NeedsAgent : ServerContainers()
}

class ContainersViewModel(
    private val scope: CoroutineScope,
    /** Built PER CALL, never kept */
    private val operations: suspend (Deployment) -> ContainerManaging,
    private val release: suspend (Deployment) -> Unit = {},
) {
    private val _states = MutableStateFlow<Map<String, ServerContainers>>(emptyMap())
    val states: StateFlow<Map<String, ServerContainers>> = _states.asStateFlow()

    private val _isRefreshing = MutableStateFlow(false)
    val isRefreshing: StateFlow<Boolean> = _isRefreshing.asStateFlow()

    private val _busy = MutableStateFlow<Set<String>>(emptySet())
    val busy: StateFlow<Set<String>> = _busy.asStateFlow()

    private var known: Map<String, Deployment> = emptyMap()

    private var job: Job? = null

    fun load(deployments: List<Deployment>) {
        job?.cancel()
        job = scope.launch { read(deployments) }
    }

    private suspend fun read(deployments: List<Deployment>) {
        _isRefreshing.value = true
        known = known + deployments.associateBy { it.id }
        try {
            val answers = coroutineScope {
                deployments.map { deployment ->
                    async { deployment.id to state(deployment) }
                }.awaitAll()
            }
            val live = deployments.map { it.id }.toSet()
            _states.value = (_states.value + answers).filterKeys { it in live }
            known = known.filterKeys { it in live }
        } finally {
            _isRefreshing.value = false
        }
    }

    private suspend fun state(deployment: Deployment): ServerContainers {
        if (!deployment.usesAgent) return ServerContainers.NeedsAgent
        return try {
            ServerContainers.Loaded(operations(deployment).inventory())
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            release(deployment)
            ServerContainers.Failed(reason(failure))
        }
    }

    fun summary(deploymentID: String): String {
        val state = _states.value[deploymentID]
        return if (state is ServerContainers.Loaded && state.inventory.unavailableReason == null) {
            state.inventory.groups.size.toString()
        } else {
            "—"
        }
    }

    fun rename(deployment: Deployment, key: String, to: String) {
        scope.launch { apply(deployment, key) { it.rename(key, to) } }
    }

    /** Start / stop / restart a group, then RE-READ */
    fun control(deployment: Deployment, key: String, action: ContainerAction) {
        scope.launch {
            _busy.value = _busy.value + key
            try {
                operations(deployment).control(key, action)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                _states.value = _states.value + (deployment.id to
                    ServerContainers.Failed(reason(failure)))
                _busy.value = _busy.value - key
                return@launch
            }
            apply(deployment, key) { it.inventory() }
        }
    }

    /** One container's detail */
    suspend fun detail(deployment: Deployment, container: String): ContainerDetail? = try {
        operations(deployment).inspect(container)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        release(deployment)
        _states.value = _states.value + (deployment.id to ServerContainers.Failed(reason(failure)))
        null
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    private val _run = MutableStateFlow<GroupRun?>(null)
    val run: StateFlow<GroupRun?> = _run.asStateFlow()

    private var runJob: Job? = null

    private var runDeployment: Deployment? = null
    private var runNotice: OperationNotice? = null

    fun start(
        deployment: Deployment,
        key: String,
        kind: GroupOperationKind,
        purgeData: Boolean = false,
        purgeBackups: Boolean = false,
        skipBackup: Boolean = false,
    ) {
        runJob?.cancel()
        runDeployment = deployment
        _run.value = GroupRun(key = key, kind = kind, skippedBackup = skipBackup)
        runJob = scope.launch {
            _busy.value = _busy.value + key
            val notice = startNotice(deployment, key, kind).also { runNotice = it }
            try {
                val host = operations(deployment)
                val events: Flow<Any> = when (kind) {
                    GroupOperationKind.UPDATE -> host.update(key, skipBackup)
                    GroupOperationKind.BACKUP -> host.runBackup(key)
                    GroupOperationKind.REMOVE -> host.remove(key, purgeData, purgeBackups)
                }
                events.catch { failure -> fail(deployment, failure) }.collect { event -> record(event) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                fail(deployment, failure)
            }
            _run.value = _run.value?.copy(isRunning = false)
            _run.value?.let { run -> notice.finish(run.lines.lastOrNull().orEmpty(), run.failure) }
            apply(deployment, key) { it.inventory() }
        }
    }

    private fun startNotice(deployment: Deployment, key: String, kind: GroupOperationKind): OperationNotice {
        val loaded = _states.value[deployment.id.toString()] as? ServerContainers.Loaded
        val name = loaded?.inventory?.groups?.firstOrNull { it.key == key }?.displayName ?: key
        val (title, noticeKind) = when (kind) {
            GroupOperationKind.UPDATE -> R.string.updates_updating to OperationKind.UPDATE
            GroupOperationKind.BACKUP -> R.string.backups_running to OperationKind.BACKUP
            GroupOperationKind.REMOVE -> R.string.notice_removing to OperationKind.REMOVAL
        }
        return OperationNotices.start(title, name, server = deployment.name, kind = noticeKind)
            .also { it.stopsAgentJobs(deployment) }
    }

    private fun record(event: Any) {
        val current = _run.value ?: return
        val (text, outcome) = when (event) {
            is ContainerUpdateEvent -> event.text to outcomeOf(event)
            is ContainerBackupRunEvent -> event.text to outcomeOf(event)
            is ContainerRemovalEvent -> event.text to outcomeOf(event)
            else -> return
        }
        if (text.isNotEmpty()) runNotice?.update(text)
        _run.value = current.copy(
            lines = if (text.isEmpty()) current.lines else current.lines.appendBounded(text),
            outcome = outcome ?: current.outcome,
        )
    }

    private suspend fun fail(deployment: Deployment, failure: Throwable) {
        if (failure is CancellationException) throw failure
        release(deployment)
        _run.value = _run.value?.copy(failure = failure.message ?: failure::class.simpleName.orEmpty())
    }

    fun updateWithoutBackup() {
        val current = _run.value ?: return
        val deployment = runDeployment ?: return
        if (!current.mayUpdateWithoutBackup) return
        start(deployment, current.key, GroupOperationKind.UPDATE, skipBackup = true)
    }

    /** Forgets the finished run */
    fun dismissRun() {
        if (_run.value?.isRunning == true) return
        _run.value = null
    }

    /** One group's log, followed live */
    fun logs(deployment: Deployment, key: String, tail: Int = 200): Flow<ContainerLogLine> =
        flow { emitAll(operations(deployment).logs(key, tail)) }

    suspend fun backupPlan(deployment: Deployment, key: String): Result<ContainerBackupPlan> =
        ask(deployment) { it.backupPlan(key) }

    /** Stores the correction, or clears it with a null [plan] */
    suspend fun setBackupPlan(
        deployment: Deployment,
        key: String,
        plan: ContainerBackupPlan?,
    ): Result<ContainerBackupPlan> = ask(deployment) { it.setBackupPlan(key, plan) }

    suspend fun backupSchedule(deployment: Deployment, key: String): Result<ContainerBackupSchedule> =
        ask(deployment) { it.backupSchedule(key) }

    /** The archives this group's runs have left — see [ContainerManaging.backups] */
    suspend fun backups(deployment: Deployment, key: String): Result<ContainerBackupListing> =
        ask(deployment) { it.backups(key) }

    suspend fun setBackupSchedule(
        deployment: Deployment,
        key: String,
        every: ContainerBackupCadence?,
    ): Result<ContainerBackupSchedule> = ask(deployment) { it.setBackupSchedule(key, every) }

    /** What a removal would delete, for this pair of toggles */
    suspend fun removalPreview(
        deployment: Deployment,
        key: String,
        purgeData: Boolean,
        purgeBackups: Boolean,
    ): Result<ContainerRemovalPreview> =
        ask(deployment) { it.removalPreview(key, purgeData, purgeBackups) }

    private suspend fun <T> ask(
        deployment: Deployment,
        call: suspend (ContainerManaging) -> T,
    ): Result<T> = try {
        Result.success(call(operations(deployment)))
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        release(deployment)
        Result.failure(failure)
    }

    private suspend fun apply(
        deployment: Deployment,
        key: String,
        call: suspend (ContainerManaging) -> ContainerInventory,
    ) {
        _states.value = _states.value + (deployment.id to try {
            ServerContainers.Loaded(call(operations(deployment)))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            release(deployment)
            ServerContainers.Failed(reason(failure))
        })
        _busy.value = _busy.value - key
    }

    private fun reason(failure: Exception): String =
        failure.message ?: failure::class.simpleName.orEmpty()
}
