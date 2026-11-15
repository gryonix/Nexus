package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationNotice
import com.skaymer.gryonixnexus.app.notify.OperationKind
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.RebootSchedule
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.SystemUpdate
import com.skaymer.gryonixnexus.servercontrol.SystemUpdateOperations
import com.skaymer.gryonixnexus.servercontrol.SystemUpdateStatus
import com.skaymer.gryonixnexus.servercontrol.SystemUpdaterMissing
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** One machine's package updates as the screen draws them */
data class HostSystemUpdate(
    val status: SystemUpdateStatus? = null,
    val missing: Boolean = false,
    val busy: Boolean = false,
    val errorMessage: String? = null,
)

/** Package updates of each machine, polled while one runs */
class SystemUpdateViewModel(
    private val scope: CoroutineScope,
    private val runners: suspend (Deployment) -> SSHCommandRunner,
    private val release: suspend (Deployment) -> Unit = {},
) {
    private val _hosts = MutableStateFlow<Map<SSHHostID, HostSystemUpdate>>(emptyMap())
    val hosts: StateFlow<Map<SSHHostID, HostSystemUpdate>> = _hosts.asStateFlow()

    private var polling: Job? = null
    /** A run's notification, by server and machine */
    private val notices = mutableMapOf<Pair<String, SSHHostID>, OperationNotice>()

    fun load(deployment: Deployment) {
        _hosts.value = emptyMap()
        scope.launch {
            deployment.nodes.forEach { node ->
                perform(deployment, node.sshHost) { it.status(node.sshHost) }
                followNotice(deployment, node.sshHost)
            }
            poll(deployment)
        }
    }

    fun start(deployment: Deployment, host: SSHHostID) {
        scope.launch {
            notices[deployment.id to host] = OperationNotices.start(
                R.string.notice_updating_system, server = deployment.name, kind = OperationKind.UPDATE,
            )
            perform(deployment, host) { it.start(host) }
            followNotice(deployment, host)
            poll(deployment)
        }
    }

    /** Mirrors one machine's run in its notification */
    private fun followNotice(deployment: Deployment, host: SSHHostID) {
        val notice = notices[deployment.id to host] ?: return
        val state = _hosts.value[host] ?: return
        val status = state.status
        when {
            state.errorMessage != null -> notice.finish("", state.errorMessage)
            status?.isRunning == true -> return notice.update(status.log.lastOrNull().orEmpty())
            (status?.exitCode ?: 0) != 0 -> notice.finish("", status?.log?.lastOrNull())
            else -> notice.finish(OperationNotices.text(R.string.notice_system_current))
        }
        notices.remove(deployment.id to host)
    }

    fun setSchedule(deployment: Deployment, host: SSHHostID, schedule: CommandCatalog.Backups.Schedule) {
        scope.launch { perform(deployment, host, { it.copy(schedule = schedule) }) { it.setSchedule(schedule, host) } }
    }

    fun setRebootSchedule(deployment: Deployment, host: SSHHostID, schedule: RebootSchedule) {
        scope.launch {
            perform(deployment, host, { it.copy(rebootSchedule = schedule) }) { it.setRebootSchedule(schedule, host) }
        }
    }

    fun setSwap(deployment: Deployment, host: SSHHostID, sizeGB: Int?) {
        scope.launch { perform(deployment, host) { it.setSwap(sizeGB, host) } }
    }

    fun setAtStop(deployment: Deployment, host: SSHHostID, part: SystemUpdate.Part, on: Boolean) {
        scope.launch {
            perform(deployment, host, {
                if (part == SystemUpdate.Part.SYSTEM) it.copy(systemAtStop = on) else it.copy(appsAtStop = on)
            }) { it.setAtStop(part, on, host) }
        }
    }

    fun setAtStart(deployment: Deployment, host: SSHHostID, part: SystemUpdate.Part, on: Boolean) {
        scope.launch {
            perform(deployment, host, {
                if (part == SystemUpdate.Part.SYSTEM) it.copy(systemAtStart = on) else it.copy(appsAtStart = on)
            }) { it.setAtStart(part, on, host) }
        }
    }

    private suspend fun perform(
        deployment: Deployment,
        host: SSHHostID,
        demoChange: (SystemUpdateStatus) -> SystemUpdateStatus = { it },
        work: suspend (SystemUpdateOperations) -> SystemUpdateStatus,
    ) {
        if (DemoDeployments.isDemoID(deployment.id)) {
            edit(host) { HostSystemUpdate(status = demoChange(demo(it.status))) }
            return
        }
        edit(host) { it.copy(busy = true) }
        try {
            val status = work(SystemUpdateOperations(runners(deployment)))
            edit(host) { HostSystemUpdate(status = status) }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (missing: SystemUpdaterMissing) {
            edit(host) { HostSystemUpdate(missing = true) }
        } catch (failure: Exception) {
            release(deployment)
            edit(host) { it.copy(busy = false, errorMessage = failure.message ?: failure.toString()) }
        }
    }

    private fun demo(previous: SystemUpdateStatus?): SystemUpdateStatus =
        (previous ?: SystemUpdateStatus(schedule = CommandCatalog.Backups.Schedule.Off, rebootSchedule = RebootSchedule.Off)).copy(
            isRunning = false,
            exitCode = 0,
            finished = System.currentTimeMillis() / 1000 - if (previous == null) 2 * 86_400 else 0,
            log = listOf("0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded."),
            swapBytes = 2_147_483_648,
            offersAtStop = true,
        )

    private fun edit(host: SSHHostID, change: (HostSystemUpdate) -> HostSystemUpdate) {
        _hosts.update { it + (host to change(it[host] ?: HostSystemUpdate())) }
    }

    private fun poll(deployment: Deployment) {
        if (polling?.isActive == true || _hosts.value.values.none { it.status?.isRunning == true }) return
        polling = scope.launch {
            while (_hosts.value.values.any { it.status?.isRunning == true }) {
                delay(3_000)
                _hosts.value.filterValues { it.status?.isRunning == true }.keys.forEach { host ->
                    perform(deployment, host) { it.status(host) }
                    followNotice(deployment, host)
                }
            }
        }
    }
}
