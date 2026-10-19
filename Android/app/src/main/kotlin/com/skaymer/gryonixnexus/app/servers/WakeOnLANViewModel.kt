package com.skaymer.gryonixnexus.app.servers

import gryonixnexusd.v1.WakeOnLANInfo
import gryonixnexusd.v1.WakeSupport
import com.skaymer.gryonixnexus.app.net.MagicPacketSender
import com.skaymer.gryonixnexus.catalog.HomePlacement
import com.skaymer.gryonixnexus.core.WakeOnLAN
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.StatusOperations
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class WakeOnLANViewModel(
    private val scope: CoroutineScope,
    private val runners: suspend (Deployment) -> SSHCommandRunner,
    /** Writes the machine's MAC back onto the fleet's own copy */
    private val save: (Deployment) -> Unit,
    private val release: suspend (Deployment) -> Unit = {},
    /** The agent's own reading of the network card */
    private val agentReading: suspend (Deployment) -> WakeOnLANInfo? = { null },
    /** Swapped in tests — a real send touches the network */
    private val sendFromPhone: (ByteArray, String, Int) -> Boolean = MagicPacketSender::send,
) {
    data class State(
        val isWorking: Boolean = false,
        val note: Note? = null,
        val support: WakeSupport = WakeSupport.WAKE_SUPPORT_UNKNOWN,
    )

    sealed interface Note {
        data class Sent(val from: String) : Note
        data class SentFromPhone(val broadcast: String) : Note
        data object NoMACYet : Note
        data object CardCannotWake : Note
        data object ThePhoneCouldNotSend : Note
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    /** Refreshes the stored address while the machine is awake */
    fun refreshQuietly(deployment: Deployment) {
        if (!isOffered(deployment)) return
        scope.launch { readFrom(deployment) }
    }

    private suspend fun readFrom(deployment: Deployment): WakeOnLAN.Read? {
        val target = target(deployment) ?: return null
        val found = fromAgent(deployment, target) ?: overSSH(deployment, target) ?: return null
        if (found.mac != deployment.wakeOnLANMAC || found.broadcast != deployment.wakeOnLANBroadcast) {
            save(deployment.copy(wakeOnLANMAC = found.mac, wakeOnLANBroadcast = found.broadcast))
        }
        return found
    }

    private suspend fun fromAgent(deployment: Deployment, target: DeploymentNode): WakeOnLAN.Read? {
        if (!deployment.usesAgent || target.sshHost != deployment.servicesHost) return null
        val info = try {
            agentReading(deployment)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            null
        } ?: return null
        _state.value = _state.value.copy(support = info.support)
        val mac = WakeOnLAN.normalised(info.mac) ?: return null
        return WakeOnLAN.Read(mac, info.broadcast.ifEmpty { null })
    }

    private suspend fun overSSH(deployment: Deployment, target: DeploymentNode): WakeOnLAN.Read? =
        try {
            StatusOperations(runners(deployment), deployment.dashboardConfig).wakeInfo(target.sshHost)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            release(deployment)
            null
        }

    /** One-tap wake with the address the machine gave */
    fun wake(deployment: Deployment) {
        run {
            val stored = deployment.wakeOnLANMAC?.let { WakeOnLAN.normalised(it) }
            val read = if (stored == null) readFrom(deployment) else null
            val normalised = stored ?: read?.mac ?: return@run Note.NoMACYet
            if (_state.value.support == WakeSupport.WAKE_SUPPORT_UNSUPPORTED) return@run Note.CardCannotWake
            val current = if (read != null) {
                deployment.copy(wakeOnLANMAC = read.mac, wakeOnLANBroadcast = read.broadcast)
            } else {
                deployment
            }
            send(current, normalised)
        }
    }

    fun clearNote() {
        _state.value = _state.value.copy(note = null)
    }

    private suspend fun send(deployment: Deployment, normalised: String): Note {
        val target = target(deployment)
        val broadcast = target?.let { broadcast(deployment, it) } ?: WakeOnLAN.LIMITED_BROADCAST
        val peer = target?.let { home ->
            deployment.nodes.firstOrNull { it.sshHost != home.sshHost && broadcast(deployment, it) == broadcast }
        }
        if (peer != null && sendFrom(deployment, peer, normalised, broadcast)) {
            return Note.Sent(peer.endpoint.host)
        }
        val packet = WakeOnLAN.magicPacket(normalised) ?: return Note.NoMACYet
        return if (sendFromPhone(packet, broadcast, WakeOnLAN.PORT)) {
            Note.SentFromPhone(broadcast)
        } else {
            Note.ThePhoneCouldNotSend
        }
    }

    private suspend fun broadcast(deployment: Deployment, node: DeploymentNode): String {
        val host = node.endpoint.host
        val stored = deployment.wakeOnLANBroadcast.takeIf { node.sshHost == target(deployment)?.sshHost }
        val resolved = if (WakeOnLAN.broadcastAddress(host) == null) {
            withContext(Dispatchers.IO) { WakeOnLAN.resolveIPv4(host) }
        } else {
            null
        }
        return WakeOnLAN.broadcast(stored, host, resolved)
    }

    private suspend fun sendFrom(deployment: Deployment, peer: DeploymentNode, mac: String, broadcast: String): Boolean =
        try {
            StatusOperations(runners(deployment), deployment.dashboardConfig).sendWakeOnLAN(mac, broadcast, peer.sshHost)
            true
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            release(deployment)
            false
        }

    private fun target(deployment: Deployment) = homeMachine(deployment)

    private fun run(body: suspend () -> Note) {
        if (_state.value.isWorking) return
        _state.value = _state.value.copy(isWorking = true, note = null)
        scope.launch {
            val note = body()
            _state.value = _state.value.copy(isWorking = false, note = note)
        }
    }

    companion object {
        fun isOffered(deployment: Deployment): Boolean = homeMachine(deployment) != null

        fun homeMachine(deployment: Deployment): DeploymentNode? {
            deployment.nodes.firstOrNull { it.legacySlot == DeploymentNode.LegacySlot.HOME }
                ?.let { return it }
            if (HomePlacement.impliesHome(deployment.scope) || deployment.serviceSettings.machineAtHome) {
                return deployment.nodes.firstOrNull { it.runsServices } ?: deployment.nodes.firstOrNull()
            }
            return deployment.nodes.firstOrNull { WakeOnLAN.isLocalNetwork(it.endpoint.host) }
        }
    }
}
