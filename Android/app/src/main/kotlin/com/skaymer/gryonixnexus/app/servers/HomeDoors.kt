package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Plain HTTP app ports at home, per server */
class HomeDoors(
    private val scope: CoroutineScope,
    private val client: suspend (Deployment) -> AgentClient,
) {
    private val _doors = MutableStateFlow<Map<String, Map<String, Int>>>(emptyMap())
    val doors: StateFlow<Map<String, Map<String, Int>>> = _doors.asStateFlow()

    private val _mesh = MutableStateFlow<Map<String, String>>(emptyMap())
    /** Each server's address in the Tailscale mesh */
    val mesh: StateFlow<Map<String, String>> = _mesh.asStateFlow()

    fun load(deployment: Deployment) {
        if (!deployment.usesAgent) return
        scope.launch {
            val state = try {
                client(deployment).getState()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                return@launch
            }
            val key = deployment.id.toString()
            _doors.value = _doors.value + (key to state.home_doors.associate { it.service_id to it.port })
            _mesh.value = if (state.mesh_address.isEmpty()) _mesh.value - key else _mesh.value + (key to state.mesh_address)
        }
    }

    companion object {
        /** The address apps use at home for one service */
        fun url(deployment: Deployment, port: Int): String {
            val host = deployment.nodes.firstOrNull { it.sshHost == deployment.servicesHost }?.endpoint?.host
                ?: deployment.entry.host
            val bracketed = if (host.contains(":")) "[$host]" else host
            return "http://$bracketed:$port"
        }

        /** The same door reached through the VPN */
        fun meshURL(address: String, port: Int): String = "http://$address:$port"
    }
}
