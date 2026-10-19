package com.skaymer.gryonixnexus.app.speed

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.app.install.StoragePreparation
import com.skaymer.gryonixnexus.catalog.storage.ServerHardware
import com.skaymer.gryonixnexus.catalog.storage.SpeedTest
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the speed screen shows for one machine */
data class SpeedState(
    val locations: List<String> = listOf(SpeedTest.SYSTEM_DIRECTORY),
    val records: List<SpeedRecord> = emptyList(),
    /** The location being tested; "" for the internet */
    val running: String? = null,
    val failure: Failure? = null,
) {
    enum class Failure { NO_CURL, NO_ANSWER, NO_NUMBERS, OTHER }

    fun latest(location: String?): SpeedRecord? = records.firstOrNull { it.location == location }
}

/** Runs disk and internet tests; data disks run with sudo */
class SpeedTestViewModel(
    private val scope: CoroutineScope,
    private val history: SpeedTestHistory,
    private val control: suspend (Deployment) -> SSHCommandRunner,
) {
    private val _state = MutableStateFlow(SpeedState())
    val state: StateFlow<SpeedState> = _state.asStateFlow()
    var failureDetail: String? = null
        private set

    /** Mounted arrays and cache disks join the system disk */
    fun load(deployment: Deployment, host: SSHHostID) {
        _state.value = SpeedState(records = history.records(deployment.id, host))
        scope.launch {
            val hardware = runCatching {
                ServerHardware.parse(control(deployment).run(ServerHardware.PROBE_COMMAND, host, 20.seconds).stdout)
            }.getOrNull() ?: return@launch
            val data = hardware.volumes.mapNotNull { it.mountpoint } + hardware.disks.mapNotNull { it.dataMount }
            val locations = (listOf(SpeedTest.SYSTEM_DIRECTORY) + data.filter { it.startsWith("/") && it != "/" }).distinct()
            _state.value = _state.value.copy(locations = locations)
        }
    }

    fun testInternet(deployment: Deployment, host: SSHHostID) = measure(deployment, host, null) {
        val output = StoragePreparation.output(SpeedTest.INTERNET_SCRIPT, SpeedTest.DONE_MARKER, control(deployment), host, false)
        if ("nocurl" in output) throw Refused(SpeedState.Failure.NO_CURL)
        val result = SpeedTest.parseInternet(output) ?: throw Refused(SpeedState.Failure.NO_ANSWER)
        SpeedRecord(System.currentTimeMillis(), internet = result)
    }

    fun testDisk(deployment: Deployment, host: SSHHostID, location: String) = measure(deployment, host, location) {
        val script = SpeedTest.diskScript(location)
        val elevated = location != SpeedTest.SYSTEM_DIRECTORY && account(deployment, host) != "root"
        val output = StoragePreparation.output(script, SpeedTest.DONE_MARKER, control(deployment), host, elevated)
        val result = SpeedTest.parseDisk(output) ?: throw Refused(SpeedState.Failure.NO_NUMBERS)
        SpeedRecord(System.currentTimeMillis(), location = location, disk = result)
    }

    private fun measure(deployment: Deployment, host: SSHHostID, location: String?, test: suspend () -> SpeedRecord) {
        if (_state.value.running != null) return
        _state.value = _state.value.copy(running = location.orEmpty(), failure = null)
        val title = if (location == null) R.string.notice_testing_internet else R.string.notice_testing_disk
        val notice = OperationNotices.start(title, server = deployment.name, text = location.orEmpty())
        scope.launch {
            val failure = try {
                history.add(test(), deployment.id, host)
                null
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (refused: Refused) {
                refused.reason
            } catch (error: Exception) {
                failureDetail = error.message ?: error.toString()
                SpeedState.Failure.OTHER
            }
            _state.value = _state.value.copy(running = null, failure = failure, records = history.records(deployment.id, host))
            notice.finish(OperationNotices.text(R.string.notice_done), failure?.let(::failureLine))
        }
    }

    private fun failureLine(failure: SpeedState.Failure): String = when (failure) {
        SpeedState.Failure.NO_CURL -> OperationNotices.text(R.string.speed_no_curl)
        SpeedState.Failure.NO_ANSWER -> OperationNotices.text(R.string.speed_no_answer)
        SpeedState.Failure.NO_NUMBERS -> OperationNotices.text(R.string.speed_no_numbers)
        SpeedState.Failure.OTHER -> failureDetail.orEmpty()
    }

    private fun account(deployment: Deployment, host: SSHHostID): String =
        deployment.nodes.firstOrNull { it.sshHost == host }?.endpoint?.user ?: deployment.entry.user

    private class Refused(val reason: SpeedState.Failure) : Exception()
}
