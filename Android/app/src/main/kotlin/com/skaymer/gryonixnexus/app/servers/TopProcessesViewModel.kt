package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ProcessSample
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.TopProcesses
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlin.time.Duration.Companion.seconds

data class TopProcessesState(
    val samples: List<ProcessSample> = emptyList(),
    val loaded: Boolean = false,
    val errorMessage: String? = null,
    /** True when the server answered with no processes */
    val empty: Boolean = false,
)

/** Reads `top` on one host every few seconds */
class TopProcessesViewModel(
    private val scope: CoroutineScope,
    private val runners: suspend (Deployment) -> SSHCommandRunner,
) {
    private val _state = MutableStateFlow(TopProcessesState())
    val state: StateFlow<TopProcessesState> = _state.asStateFlow()
    private var job: Job? = null

    fun follow(deployment: Deployment, host: SSHHostID) {
        stop()
        _state.value = TopProcessesState()
        job = scope.launch {
            while (true) {
                refresh(deployment, host)
                delay(5_000)
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    private suspend fun refresh(deployment: Deployment, host: SSHHostID) {
        try {
            val output = runners(deployment).run(TopProcesses.COMMAND, host, 20.seconds).stdout
            val samples = TopProcesses.parse(output)
            _state.value = TopProcessesState(samples, loaded = true, empty = samples.isEmpty())
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            _state.value = _state.value.copy(loaded = true, errorMessage = failure.message ?: failure.toString())
        }
    }
}
