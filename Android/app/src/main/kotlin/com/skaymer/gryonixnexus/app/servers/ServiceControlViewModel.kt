package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.ContainerStatus
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HealthLevel
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHServiceControl
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRouting
import com.skaymer.gryonixnexus.servercontrol.ServicePowerAction
import com.skaymer.gryonixnexus.servercontrol.ServiceControlling
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class ServiceState(
    val containers: List<ContainerStatus> = emptyList(),
    val isBusy: Boolean = false,
    val errorMessage: String? = null,
    val hasAnswered: Boolean = false,
)

val ServiceState.containersNeedingAttention: Int
    get() = containers.count { it.health != HealthLevel.OK }

class ServiceControlViewModel(
    private val scope: CoroutineScope,
    private val runners: suspend (Deployment) -> SSHCommandRunner,
    private val release: suspend (Deployment) -> Unit = {},
    /** How management is performed */
    private val control: suspend (Deployment, SSHCommandRunner) -> ServiceControlling =
        { deployment, runner -> SSHServiceControl(runner, deployment) },
    private val agentTransportAvailable: Boolean = false,
) {
    private val _states = MutableStateFlow<Map<ServiceID, ServiceState>>(emptyMap())
    val states: StateFlow<Map<ServiceID, ServiceState>> = _states.asStateFlow()

    private var job: Job? = null

    /** Which implementation this app uses for this server */
    fun route(deployment: Deployment): ServiceControlRoute =
        ServiceControlRouting.route(
            usesAgent = deployment.usesAgent,
            agentTransportAvailable = agentTransportAvailable,
        )

    fun refresh(deployment: Deployment) {
        job?.cancel()
        job = scope.launch {
            for (id in deployment.services) {
                val service = ServiceRegistry.service(id) ?: continue
                update(id) { it.copy(isBusy = true) }
                try {
                    val containers = control(deployment, runners(deployment)).status(service)
                    update(id) {
                        ServiceState(containers = containers, isBusy = false, hasAnswered = true)
                    }
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (failure: Exception) {
                    release(deployment)
                    update(id) {
                        it.copy(isBusy = false, errorMessage = reason(failure), hasAnswered = true)
                    }
                }
            }
        }
    }

    fun power(deployment: Deployment, id: ServiceID, action: ServicePowerAction) {
        val service = ServiceRegistry.service(id) ?: return
        scope.launch {
            update(id) { it.copy(isBusy = true, errorMessage = null) }
            try {
                val containers = control(deployment, runners(deployment)).power(action, service)
                update(id) {
                    ServiceState(containers = containers, isBusy = false, hasAnswered = true)
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                update(id) { it.copy(isBusy = false, errorMessage = reason(failure)) }
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    private fun update(id: ServiceID, change: (ServiceState) -> ServiceState) {
        val current = _states.value
        _states.value = current + (id to change(current[id] ?: ServiceState()))
    }

    private fun reason(failure: Exception): String =
        failure.message ?: failure::class.simpleName.orEmpty()
}
