package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.canRunVPNOnRelay
import com.skaymer.gryonixnexus.servercontrol.installedVPNServices
import com.skaymer.gryonixnexus.servercontrol.movingVPN
import com.skaymer.gryonixnexus.servercontrol.otherVPNHost
import com.skaymer.gryonixnexus.servercontrol.vpnHost
import com.skaymer.gryonixnexus.servercontrol.vpnRunsOnRelay
import com.skaymer.gryonixnexus.servercontrol.vpnStateDirectories
import gryonixnexusd.v1.VpnState
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** One machine's side of a VPN move */
interface VPNMoveMachine {
    suspend fun pack(directories: List<String>): VpnState

    suspend fun unpack(state: VpnState, replace: Boolean)

    /** Stops the VPN here, its data kept */
    suspend fun removeVPN()
}

/** The words a move reports in */
data class VPNMoveText(
    val movingToRelay: String = "Moving the VPN to the VPS",
    val movingHome: String = "Moving the VPN home",
    val packing: String = "Packing the VPN's keys and devices…",
    val starting: String = "Starting the VPN on the other machine…",
    val doneOnRelay: String = "The VPN runs on the VPS now. Devices keep their configurations.",
    val doneAtHome: String = "The VPN runs at home now. Devices keep their configurations.",
    val packed: (String) -> String = { "Packed the VPN's folders: $it" },
    val relayFailed: (String) -> String = { "Could not update the relay: $it" },
    val oldCopyRunning: (String) -> String = { "The old copy of the VPN is still running: $it" },
    val noSecondMachine: String = "This server has no VPS in front of it.",
    val nothingToMove: String = "This server has no VPN to move.",
)

/** What the move shows while it runs */
data class VPNMoveState(
    /** The server whose VPN moves */
    val serverID: String? = null,
    val title: String? = null,
    val progress: String? = null,
    val log: List<String> = emptyList(),
    val errorMessage: String? = null,
    val isRunning: Boolean = false,
)

/** Moves the VPN with its keys between home and relay */
class VPNMoveViewModel(
    private val scope: CoroutineScope,
    private val machine: suspend (Deployment, SSHHostID) -> VPNMoveMachine,
    /** Installs every VPN protocol of the deployment on its machine */
    private val installVPN: suspend (Deployment) -> Unit,
    private val reprovisionRelay: suspend (Deployment) -> List<String>,
    private val persist: (Deployment) -> Unit,
    private val release: suspend (Deployment) -> Unit = {},
    private val text: VPNMoveText = VPNMoveText(),
) {
    private val _state = MutableStateFlow(VPNMoveState())
    val state: StateFlow<VPNMoveState> = _state.asStateFlow()

    fun move(deployment: Deployment, toRelay: Boolean) {
        if (!offers(deployment) || deployment.vpnRunsOnRelay == toRelay || _state.value.isRunning) return
        _state.value = VPNMoveState(
            serverID = deployment.id,
            title =if (toRelay) text.movingToRelay else text.movingHome,
            progress = text.packing,
            isRunning = true,
        )
        scope.launch { run(deployment, toRelay) }
    }

    private suspend fun run(deployment: Deployment, toRelay: Boolean) {
        try {
            carry(deployment, toRelay)
            update { it.copy(progress = if (toRelay) text.doneOnRelay else text.doneAtHome, isRunning = false) }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            release(deployment)
            update { it.copy(errorMessage = reason(failure), isRunning = false) }
        }
    }

    /** Packs, unpacks, installs, then retires the old copy */
    suspend fun carry(before: Deployment, toRelay: Boolean): Deployment {
        val target = before.otherVPNHost ?: error(text.noSecondMachine)
        if (before.services.none { it in ServiceID.VPN_PROTOCOLS }) error(text.nothingToMove)
        val source = machine(before, before.vpnHost)
        val destination = machine(before, target)
        val packed = source.pack(before.vpnStateDirectories)
        note(text.packed(packed.directories.joinToString(", ")))
        destination.unpack(packed, replace = true)
        update { it.copy(progress = text.starting) }
        val moved = before.movingVPN(toRelay)
        try {
            installVPN(moved)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            undo(before, destination)
            throw failure
        }
        persist(moved)
        finish(moved, source)
        return moved
    }

    /** Clears the other machine; the relay forwards home again */
    private suspend fun undo(before: Deployment, destination: VPNMoveMachine) {
        try {
            destination.removeVPN()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
        }
        if (!before.vpnRunsOnRelay) updateRelay(before)
    }

    /** Removes the old copy, data kept */
    private suspend fun finish(moved: Deployment, source: VPNMoveMachine) {
        try {
            source.removeVPN()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            note(text.oldCopyRunning(reason(failure)))
        }
        if (!moved.vpnRunsOnRelay) updateRelay(moved)
    }

    private suspend fun updateRelay(deployment: Deployment) {
        try {
            reprovisionRelay(deployment).forEach(::note)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            note(text.relayFailed(reason(failure)))
        }
    }

    fun clear() {
        if (!_state.value.isRunning) _state.value = VPNMoveState()
    }

    private fun note(line: String) = update { it.copy(log = it.log + line) }

    private fun update(change: (VPNMoveState) -> VPNMoveState) {
        _state.value = change(_state.value)
    }

    private fun reason(failure: Exception): String = failure.message ?: failure::class.simpleName.orEmpty()

    companion object {
        /** Whether the VPN section offers the move at all */
        fun offers(deployment: Deployment): Boolean =
            deployment.canRunVPNOnRelay && deployment.installedVPNServices.isNotEmpty()
    }
}
