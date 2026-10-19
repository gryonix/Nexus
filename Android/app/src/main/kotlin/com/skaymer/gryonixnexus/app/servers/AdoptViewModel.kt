package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.agentclient.PairingCode
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import kotlin.coroutines.cancellation.CancellationException
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class AdoptResult(
    val hostname: String,
    val domains: List<String>,
    val services: Set<ServiceID>,
    val installedOutside: Set<String>,
    /** Anything the scan could not place — the agent's own words */
    val notes: List<String>,
)

data class AdoptState(
    val stage: AgentAdoption.Stage? = null,
    val result: AdoptResult? = null,
    val failure: AgentAdoption.Failure? = null,
) {
    val isRunning: Boolean get() = stage != null
}

/** Adopting a server that already runs the agent */
class AdoptViewModel(
    private val scope: CoroutineScope,
    private val runners: suspend (Deployment) -> SSHCommandRunner,
    private val clients: suspend (Deployment) -> AgentClient,
    /** The public key this device pairs under */
    private val devicePublicKey: (Deployment) -> String,
    private val deviceLabel: String,
    private val release: suspend (Deployment) -> Unit = {},
    private val deviceUID: () -> String = { "" },
) {
    private val _state = MutableStateFlow(AdoptState())
    val state: StateFlow<AdoptState> = _state.asStateFlow()

    fun reset() {
        _state.value = AdoptState()
    }

    fun start(deployment: Deployment) {
        if (_state.value.isRunning) return
        _state.value = AdoptState(stage = AgentAdoption.Stage.CONNECTING)
        scope.launch {
            val runner = try {
                runners(deployment)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                return@launch fail(deployment, AgentAdoption.failure(failure))
            }

            val client = try {
                clients(deployment)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                return@launch fail(deployment, AgentAdoption.failure(failure))
            }

            val state = try {
                client.getState()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                return@launch fail(
                    deployment,
                    AgentAdoption.Failure.NoAgent(failure.message ?: failure.toString()),
                )
            }

            _state.value = _state.value.copy(stage = AgentAdoption.Stage.PAIRING)
            try {
                val minted = runner.run(PAIR_CODE_COMMAND, deployment.servicesHost, 30.seconds)
                val code = PairingCode.parse(minted.stdout)
                    ?: error(minted.stderr.ifBlank { "the agent printed no pairing code" })
                client.pair(code, devicePublicKey(deployment), deviceLabel, deviceUID())

                _state.value = _state.value.copy(stage = AgentAdoption.Stage.DISCOVERING)
                val discovered = client.discover()
                _state.value = AdoptState(
                    result = AdoptResult(
                        hostname = state.host?.hostname.orEmpty(),
                        domains = state.host?.domains.orEmpty(),
                        services = AgentAdoption.services(
                            discovered.services.map { it.id to it.containers.map { c -> c.name } },
                        ),
                        installedOutside = state.services
                            .filter { it.installed_outside }
                            .map { it.id }
                            .toSet(),
                        notes = discovered.notes,
                    ),
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                fail(
                    deployment,
                    AgentAdoption.Failure.AgentFailed(failure.message ?: failure.toString()),
                )
            }
        }
    }

    private suspend fun fail(deployment: Deployment, failure: AgentAdoption.Failure) {
        release(deployment)
        _state.value = AdoptState(failure = failure)
    }

    companion object {
        const val PAIR_CODE_COMMAND = "sudo /usr/local/bin/gryonixnexusd pair-code"
    }
}
