package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Takes the agent off a server, keeping services and settings */
class AgentRemoval(
    private val scope: CoroutineScope,
    private val remove: suspend (Deployment) -> Unit,
    /** Writes the deployment back without the agent */
    private val save: (Deployment) -> Unit,
) {
    sealed interface Outcome {
        data object Removed : Outcome
        data object TooOld : Outcome
        data class Failed(val message: String) : Outcome
    }

    data class State(val isRunning: Boolean = false, val outcome: Outcome? = null)

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    fun remove(deployment: Deployment) {
        if (_state.value.isRunning || !deployment.usesAgent) return
        _state.value = State(isRunning = true)
        scope.launch {
            val outcome = try {
                remove.invoke(deployment)
                save(deployment.copy(usesAgent = false))
                Outcome.Removed
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (tooOld: AgentError.Rpc) {
                if (tooOld.code == "not_found") Outcome.TooOld else Outcome.Failed(tooOld.text)
            } catch (failure: Exception) {
                Outcome.Failed(failure.message ?: failure::class.simpleName.orEmpty())
            }
            _state.value = State(outcome = outcome)
        }
    }

    fun clear() {
        _state.value = State()
    }
}
