package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import gryonixnexusd.v1.SystemSettings
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** One machine's clock and name as the screen draws them */
data class HostSystemSettings(
    val settings: SystemSettings? = null,
    val busy: Boolean = false,
    val errorMessage: String? = null,
)

class SystemSettingsViewModel(
    private val scope: CoroutineScope,
    private val agent: suspend (Deployment, SSHHostID) -> AgentClient,
    private val release: suspend (Deployment) -> Unit = {},
) {
    private val _hosts = MutableStateFlow<Map<SSHHostID, HostSystemSettings>>(emptyMap())
    val hosts: StateFlow<Map<SSHHostID, HostSystemSettings>> = _hosts.asStateFlow()

    fun load(deployment: Deployment) {
        _hosts.value = emptyMap()
        if (!deployment.usesAgent) return
        deployment.nodes.forEach { node -> apply(deployment, node.sshHost) { it.getSystemSettings() } }
    }

    fun setTimeZone(deployment: Deployment, host: SSHHostID, zone: String) =
        apply(deployment, host) { it.setTimeZone(zone) }

    fun setHostName(deployment: Deployment, host: SSHHostID, name: String) =
        apply(deployment, host) { it.setHostName(name) }

    fun setTimeSync(deployment: Deployment, host: SSHHostID, enabled: Boolean) =
        apply(deployment, host) { it.setTimeSync(enabled) }

    private fun apply(deployment: Deployment, host: SSHHostID, call: suspend (AgentClient) -> SystemSettings) {
        scope.launch {
            _hosts.update { it + (host to (it[host] ?: HostSystemSettings()).copy(busy = true)) }
            try {
                val settings = call(agent(deployment, host))
                _hosts.update { it + (host to HostSystemSettings(settings = settings)) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                fail(host, failure)
            }
        }
    }

    private fun fail(host: SSHHostID, failure: Exception) {
        _hosts.update { all ->
            val known = all[host]?.settings ?: return@update all - host
            all + (host to HostSystemSettings(settings = known, errorMessage = failure.message ?: failure.toString()))
        }
    }
}
