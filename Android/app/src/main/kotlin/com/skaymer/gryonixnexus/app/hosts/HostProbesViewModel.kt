package com.skaymer.gryonixnexus.app.hosts

import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.DiskMount
import com.skaymer.gryonixnexus.servercontrol.MemoryUsage
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.WGStatus
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What one machine's block is showing */
data class HostProbeState(
    val disk: List<DiskMount>? = null,
    val diskFailed: String? = null,
    val memory: MemoryUsage? = null,
    val memoryFailed: String? = null,
    val wireGuard: WGStatus? = null,
    val wireGuardFailed: String? = null,
    val hasAnswered: Boolean = false,
)

/** The per-machine block: WireGuard, memory and disk */
class HostProbesViewModel(
    private val scope: CoroutineScope,
    private val disk: suspend (Deployment, SSHHostID) -> List<DiskMount>,
    private val memory: suspend (Deployment, SSHHostID) -> MemoryUsage,
    private val wireGuard: suspend (Deployment, SSHHostID) -> WGStatus,
) {
    private val _state = MutableStateFlow<Map<SSHHostID, HostProbeState>>(emptyMap())
    val state: StateFlow<Map<SSHHostID, HostProbeState>> = _state.asStateFlow()

    private var job: Job? = null

    fun load(deployment: Deployment) {
        job?.cancel()
        job = scope.launch {
            for (node in deployment.nodes) {
                val host = node.sshHost
                var here = HostProbeState(hasAnswered = true)
                here = try {
                    here.copy(memory = memory(deployment, host))
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (failure: Exception) {
                    here.copy(memoryFailed = failure.message ?: "could not read memory")
                }
                publish(host, here)

                here = try {
                    here.copy(disk = disk(deployment, host))
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (failure: Exception) {
                    here.copy(diskFailed = failure.message ?: "could not read the disk")
                }
                publish(host, here)

                if (showsWireGuard(deployment, node)) {
                    here = try {
                        here.copy(wireGuard = wireGuard(deployment, host))
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (failure: Exception) {
                        here.copy(wireGuardFailed = failure.message ?: "could not read WireGuard")
                    }
                    publish(host, here)
                }
            }
        }
    }

    fun reset() {
        job?.cancel()
        job = null
        _state.value = emptyMap()
    }

    private fun publish(host: SSHHostID, value: HostProbeState) {
        _state.value = _state.value + (host to value)
    }

    companion object {
        fun showsWireGuard(deployment: Deployment, node: DeploymentNode): Boolean =
            deployment.hasRelayIngress && node.legacySlot != null
    }
}
