package com.skaymer.gryonixnexus.app.storage

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationNotice
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.app.agent.AgentOutdated
import com.skaymer.gryonixnexus.app.install.InstallTarget
import com.skaymer.gryonixnexus.app.install.StoragePreparation
import com.skaymer.gryonixnexus.app.install.StorageStep
import com.skaymer.gryonixnexus.catalog.storage.DiskJob
import com.skaymer.gryonixnexus.catalog.storage.ServerHardware
import com.skaymer.gryonixnexus.catalog.storage.StorageArray
import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.core.ArtifactKind
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the disks screen shows for one machine */
data class StorageState(
    val hardware: ServerHardware? = null,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val running: Boolean = false,
    val stepFailure: String? = null,
    val outdatedAgent: Boolean = false,
    /** What the last step printed */
    val lastOutput: String? = null,
) {
    val arrays: List<StorageArray> get() = hardware?.let { StorageArray.all(it) }.orEmpty()

    /** A job, rebuild or check is under way */
    val isBusy: Boolean
        get() = hardware?.diskJob?.outcome == DiskJob.Outcome.RUNNING ||
            arrays.any { it.state is StorageArray.State.Rebuilding || it.state is StorageArray.State.Checking }
}

/** Disk health as control user; repairs as root */
class StorageViewModel(
    private val scope: CoroutineScope,
    private val control: suspend (Deployment) -> SSHCommandRunner,
    private val root: (String, InstallTarget) -> SSHCommandRunner,
    /** The agent on a machine, for steps it runs itself */
    private val agent: suspend (Deployment, SSHHostID) -> AgentClient? = { _, _ -> null },
) {
    private val _state = MutableStateFlow(StorageState())
    val state: StateFlow<StorageState> = _state.asStateFlow()

    /** Re-reads the disks while a job, rebuild or check runs */
    suspend fun follow(deployment: Deployment, host: SSHHostID) {
        try {
            while (_state.value.isBusy) {
                delay(10.seconds)
                read(deployment, host)
                notice?.update(busyLine(), busyProgress())
            }
        } finally {
            finishNotice()
        }
    }

    private var notice: OperationNotice? = null

    private fun busyProgress(): Double? = _state.value.arrays.firstNotNullOfOrNull { array ->
        when (val state = array.state) {
            is StorageArray.State.Rebuilding -> state.percent / 100
            is StorageArray.State.Checking -> state.percent / 100
            else -> null
        }
    }

    private fun busyLine(): String = _state.value.arrays.firstNotNullOfOrNull { array ->
        when (array.state) {
            is StorageArray.State.Rebuilding -> OperationNotices.text(R.string.notice_rebuilding, array.name)
            is StorageArray.State.Checking -> OperationNotices.text(R.string.notice_checking, array.name)
            else -> null
        }
    }.orEmpty()

    private fun finishNotice() {
        val shown = notice ?: return
        notice = null
        val state = _state.value
        when {
            state.isBusy -> shown.finish(OperationNotices.text(R.string.notice_continues))
            else -> shown.finish(OperationNotices.text(R.string.notice_done), state.stepFailure)
        }
    }

    fun load(deployment: Deployment, host: SSHHostID) {
        _state.value = _state.value.copy(isLoading = true, errorMessage = null)
        scope.launch { read(deployment, host) }
    }

    private suspend fun read(deployment: Deployment, host: SSHHostID) {
        try {
            val result = control(deployment).run(ServerHardware.PROBE_COMMAND, host, 20.seconds)
            val hardware = ServerHardware.parse(result.stdout)
            _state.value = _state.value.copy(
                hardware = hardware, isLoading = false,
                errorMessage = if (hardware == null) "The server did not answer the disk check." else null,
            )
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            _state.value = _state.value.copy(isLoading = false, errorMessage = failure.message ?: failure.toString())
        }
    }

    /** Mounted arrays a service can keep its data on */
    suspend fun dataArrays(deployment: Deployment): List<StorageArray> = try {
        val result = control(deployment).run(ServerHardware.PROBE_COMMAND, deployment.servicesHost, 20.seconds)
        ServerHardware.parse(result.stdout)?.let { StorageArray.all(it) }.orEmpty().filter(::holdsData)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        emptyList()
    }

    /** Running, mounted, and not the cache mirror */
    private fun holdsData(array: StorageArray): Boolean =
        !array.mountpoint.isNullOrEmpty() && !array.isCacheMirror &&
            array.state != StorageArray.State.Stopped && array.state != StorageArray.State.Unknown

    /** Runs one step over the server's own account */
    fun runAsServer(deployment: Deployment, host: SSHHostID, step: StorageStep) {
        val node = deployment.nodes.firstOrNull { it.sshHost == host } ?: return
        finishing(deployment, host) {
            agentOutput(deployment, host, step) ?: StoragePreparation.output(
                step.script, step.doneMarker, control(deployment), host, elevated = node.endpoint.user != "root",
            )
        }
    }

    /** The step run by the agent, when it can */
    private suspend fun agentOutput(deployment: Deployment, host: SSHHostID, step: StorageStep): String? {
        val task = step.agentTask ?: return null
        if (!deployment.usesAgent) return null
        val client = agent(deployment, host) ?: return null
        val result = try {
            client.runStorageTask(task)
        } catch (missing: AgentError.Rpc) {
            if (missing.code == "not_found") return null
            throw missing
        }
        check(result.output.contains(step.doneMarker)) {
            result.output.lines().filter { it.isNotBlank() }.takeLast(6).joinToString("\n")
        }
        return result.output
    }

    /** Runs one repair as root, then reads the disks again */
    fun run(deployment: Deployment, host: SSHHostID, username: String, secret: InstallTarget.Secret, step: StorageStep) {
        val node = deployment.nodes.firstOrNull { it.sshHost == host } ?: return
        finishing(deployment, host) {
            val target = InstallTarget(
                kind = InstallTarget.Kind.SINGLE,
                script = Artifact(fileName = "storage.sh", kind = ArtifactKind.SHELL_SCRIPT, contents = "", summary = ""),
                slot = (host.kind as? SSHHostID.Kind.Slot)?.slot ?: DeploymentNode.LegacySlot.VPS,
                address = node.endpoint.host, port = node.endpoint.port, username = username.trim(), secret = secret,
            )
            StoragePreparation.output(
                step.script, step.doneMarker, root(deployment.id, target), SSHHostID.VPS,
                elevated = username.trim() != "root",
            )
        }
    }

    private fun finishing(deployment: Deployment, host: SSHHostID, work: suspend () -> String) {
        _state.value = _state.value.copy(running = true, stepFailure = null, outdatedAgent = false, lastOutput = null)
        notice?.finish("")
        notice = OperationNotices.start(R.string.notice_storage, server = deployment.name)
        scope.launch {
            var output: String? = null
            var outdated = false
            val failure = try {
                output = work()
                null
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                outdated = AgentOutdated.matches(error)
                error.message ?: error.toString()
            }
            _state.value = _state.value.copy(
                running = false, stepFailure = failure, outdatedAgent = outdated, lastOutput = output,
            )
            read(deployment, host)
            if (_state.value.isBusy && failure == null) notice?.update(busyLine(), busyProgress()) else finishNotice()
        }
    }
}
