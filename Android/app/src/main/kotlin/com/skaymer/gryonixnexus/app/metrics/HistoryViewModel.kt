package com.skaymer.gryonixnexus.app.metrics

import com.skaymer.gryonixnexus.servercontrol.DiskHistoryPoint
import com.skaymer.gryonixnexus.servercontrol.DiskHistoryProbe
import com.skaymer.gryonixnexus.servercontrol.EnergyMath
import com.skaymer.gryonixnexus.servercontrol.PowerEstimate
import com.skaymer.gryonixnexus.servercontrol.EnergyProfile
import com.skaymer.gryonixnexus.servercontrol.CoroutineSleeper
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryPoint
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryProbe
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.SleepProvider
import kotlin.coroutines.coroutineContext
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

data class HistoryState(
    val points: List<MetricsHistoryPoint> = emptyList(),
    /** Each filesystem's use, for the disk chart's picker */
    val diskPoints: List<DiskHistoryPoint> = emptyList(),
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
    val hasAnswered: Boolean = false,
)

class HistoryViewModel(
    private val scope: CoroutineScope,
    private val runners: suspend (Deployment) -> SSHCommandRunner,
    private val release: suspend (Deployment) -> Unit = {},
    private val sleeper: SleepProvider = CoroutineSleeper,
    /** Idle and full-load watts per server and machine */
    private val profiles: (String, SSHHostID) -> EnergyProfile = { _, _ -> EnergyProfile.guess(4) },
    /** Reads the machine's parts for the power estimate */
    private val detectPower: suspend (String, SSHHostID, SSHCommandRunner) -> Unit = { _, _, _ -> },
    /** The machine's parts, to complete partial sensor readings */
    private val estimates: (String, SSHHostID) -> PowerEstimate? = { _, _ -> null },
) {
    private val _state = MutableStateFlow(HistoryState())
    val state: StateFlow<HistoryState> = _state.asStateFlow()

    private var job: Job? = null
    private var current: Selection? = null

    private data class Selection(
        val deploymentID: String,
        val host: SSHHostID,
        val bucket: com.skaymer.gryonixnexus.servercontrol.MetricsHistoryBucket,
    )

    /** Show this machine over this window */
    fun show(deployment: Deployment, host: SSHHostID, range: HistoryRange) {
        val wanted = Selection(deployment.id, host, range.bucket)
        if (wanted == current && job?.isActive == true) return
        current = wanted
        job?.cancel()
        _state.value = HistoryState(isLoading = true)
        job = scope.launch { poll(deployment, host, range) }
    }

    fun detached(): HistoryViewModel = HistoryViewModel(scope, runners, release, sleeper, profiles, detectPower, estimates)

    /** The screen went away */
    fun stop() {
        job?.cancel()
        job = null
        current = null
    }

    private suspend fun poll(deployment: Deployment, host: SSHHostID, range: HistoryRange) {
        val timeout = deployment.timeouts.quickSeconds.seconds
        while (coroutineContext.isActive) {
            try {
                val runner = runners(deployment)
                val loaded = MetricsHistoryProbe(runner, timeout).history(range.bucket, host)
                detectPower(deployment.id, host, runner)
                val points = EnergyMath.filled(loaded, profiles(deployment.id, host), estimates(deployment.id, host))
                val disks = runCatching { DiskHistoryProbe(runner, timeout).history(range.bucket, host) }
                    .getOrElse { _state.value.diskPoints }
                _state.value = HistoryState(
                    points = points,
                    diskPoints = disks,
                    isLoading = false,
                    errorMessage = null,
                    hasAnswered = true,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                val kept = _state.value.points
                _state.value = HistoryState(
                    points = kept,
                    isLoading = false,
                    // A message only where there is nothing else to show.
                    errorMessage = if (kept.isEmpty()) reason(failure) else null,
                    hasAnswered = _state.value.hasAnswered,
                )
            }
            sleeper.sleep(range.refreshSeconds.seconds)
        }
    }

    private fun reason(failure: Exception): String =
        failure.message ?: failure::class.simpleName.orEmpty()
}
