package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.PortForward
import com.skaymer.gryonixnexus.servercontrol.PortForwardList
import com.skaymer.gryonixnexus.servercontrol.PortForwardState
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.transport.PortForwarder
import com.skaymer.gryonixnexus.transport.SSHJCommandRunner
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/** Saved port forwards and the ones running now */
class PortForwardManager(
    private val store: SettingsStore,
    private val runner: suspend (Deployment) -> SSHCommandRunner,
) {
    private val _forwards = MutableStateFlow(read())
    val forwards: StateFlow<List<PortForward>> = _forwards.asStateFlow()
    private val _states = MutableStateFlow<Map<String, PortForwardState>>(emptyMap())
    val states: StateFlow<Map<String, PortForwardState>> = _states.asStateFlow()
    private val running = mutableMapOf<String, PortForwarder>()

    fun save(forward: PortForward) = persist(PortForwardList.upserting(forward, _forwards.value))

    fun delete(forward: PortForward) {
        stop(forward)
        persist(PortForwardList.removing(forward.id, _forwards.value))
    }

    suspend fun start(forward: PortForward, deployment: Deployment) {
        if (_states.value[forward.id]?.isActive == true) return
        mark(forward, PortForwardState.Starting)
        try {
            val ssh = runner(deployment) as? SSHJCommandRunner
                ?: error("this connection cannot forward ports")
            val forwarder = PortForwarder(ssh.sshClient(SSHHostID.VPS))
            forwarder.start(forward.localPort, forward.remoteHost, forward.remotePort)
            synchronized(running) { running[forward.id] = forwarder }
            mark(forward, PortForwardState.Running(0))
        } catch (failure: Exception) {
            mark(forward, PortForwardState.Failed(failure.message ?: failure.toString()))
        }
    }

    fun stop(forward: PortForward) {
        synchronized(running) { running.remove(forward.id) }?.stop()
        mark(forward, PortForwardState.Stopped)
    }

    fun refreshCounts() {
        val counts = synchronized(running) { running.mapValues { it.value.connections } }
        _states.update { states -> states + counts.mapValues { PortForwardState.Running(it.value) } }
    }

    private fun mark(forward: PortForward, state: PortForwardState) = _states.update { it + (forward.id to state) }

    private fun persist(updated: List<PortForward>) {
        store.setString(KEY, Json.encodeToString(serializer, updated))
        _forwards.value = updated
    }

    private fun read(): List<PortForward> =
        store.string(KEY)?.let { runCatching { Json.decodeFromString(serializer, it) }.getOrNull() }.orEmpty()

    private companion object {
        const val KEY = "portForwards.v1"
        val serializer = ListSerializer(PortForward.serializer())
    }
}
