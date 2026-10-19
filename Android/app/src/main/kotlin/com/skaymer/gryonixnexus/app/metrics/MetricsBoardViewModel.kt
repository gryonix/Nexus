package com.skaymer.gryonixnexus.app.metrics

import com.skaymer.gryonixnexus.servercontrol.CoroutineSleeper
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryPoint
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryProbe
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryReading
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.SleepProvider
import kotlin.coroutines.coroutineContext
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** What the board draws */
data class MetricsBoardState(
    val points: Map<MetricPanel.Source, List<MetricsHistoryPoint>> = emptyMap(),
    val errors: Map<String, String> = emptyMap(),
    val isLoading: Boolean = false,
    /** True once a full pass has come back */
    val hasAnswered: Boolean = false,
)

class MetricsBoardViewModel(
    private val scope: CoroutineScope,
    private val runners: suspend (Deployment) -> SSHCommandRunner,
    private val release: suspend (Deployment) -> Unit = {},
    private val readers: suspend (Deployment, SSHHostID, SSHCommandRunner) -> MetricsHistoryReading =
        { deployment, _, runner ->
            MetricsHistoryProbe(runner, deployment.timeouts.quickSeconds.seconds)
        },
    private val sleeper: SleepProvider = CoroutineSleeper,
) {
    private val _state = MutableStateFlow(MetricsBoardState())
    val state: StateFlow<MetricsBoardState> = _state.asStateFlow()

    private var job: Job? = null
    private var sources: Set<MetricPanel.Source> = emptySet()
    private var deployments: Map<String, Deployment> = emptyMap()

    /** Called whenever the panel list or the server list changes */
    fun update(panels: List<MetricPanel>, deployments: List<Deployment>) {
        this.deployments = deployments.associateBy { it.id }
        val wanted = panels.map { it.source }.toSet()
        if (wanted == sources && job?.isActive == true) return
        sources = wanted
        _state.value = _state.value.copy(
            points = _state.value.points.filterKeys { it in wanted },
        )
        job?.cancel()
        if (wanted.isEmpty()) {
            job = null
            return
        }
        job = scope.launch { poll() }
    }

    /** Stops reading */
    fun stop() {
        job?.cancel()
        job = null
        sources = emptySet()
    }

    /** Reads every tile once, now — what a pull-to-refresh asks for */
    fun refresh() {
        scope.launch { load() }
    }

    private suspend fun poll() {
        while (coroutineContext.isActive) {
            load()
            sleeper.sleep(REFRESH_SECONDS.seconds)
        }
    }

    /** Every tile at once */
    private suspend fun load() {
        val wanted = sources
        if (wanted.isEmpty()) return
        _state.value = _state.value.copy(isLoading = _state.value.points.isEmpty())
        val answers = coroutineScope {
            wanted.mapNotNull { source ->
                val deployment = deployments[source.deploymentID] ?: return@mapNotNull null
                async { source to read(deployment, source) }
            }.awaitAll()
        }

        val points = _state.value.points.toMutableMap()
        val errors = _state.value.errors.toMutableMap()
        for ((source, answer) in answers) {
            answer.fold(
                onSuccess = {
                    points[source] = it
                    errors.remove(source.deploymentID)
                },
                onFailure = { failure ->
                    if (points[source].isNullOrEmpty()) {
                        errors[source.deploymentID] = reason(failure)
                    }
                },
            )
        }
        _state.value = MetricsBoardState(
            points = points.filterKeys { it in wanted },
            errors = errors.filterKeys { id -> wanted.any { it.deploymentID == id } },
            isLoading = false,
            hasAnswered = true,
        )
    }

    private suspend fun read(
        deployment: Deployment,
        source: MetricPanel.Source,
    ): Result<List<MetricsHistoryPoint>> = try {
        val runner = runners(deployment)
        Result.success(readers(deployment, source.host, runner).history(source.bucket, source.host))
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        release(deployment)
        Result.failure(failure)
    }

    private fun reason(failure: Throwable): String =
        failure.message ?: failure::class.simpleName.orEmpty()

    companion object {
        const val REFRESH_SECONDS = 30L

        fun tiles(
            panels: List<MetricPanel>,
            state: MetricsBoardState,
        ): List<Tile> = panels.map { panel ->
            val read = state.points[panel.source]
            Tile(
                panel = panel,
                points = read.orEmpty(),
                errorMessage = state.errors[panel.deploymentID].takeIf { read.isNullOrEmpty() },
                saysThereIsNone = read != null &&
                    read.isEmpty() &&
                    state.errors[panel.deploymentID] == null,
            )
        }

        data class Tile(
            val panel: MetricPanel,
            val points: List<MetricsHistoryPoint>,
            val errorMessage: String?,
            val saysThereIsNone: Boolean,
        )
    }
}
