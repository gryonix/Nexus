package com.skaymer.gryonixnexus.app.servers

import android.content.Context
import android.os.Build
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.QuickTransferAddresses
import com.skaymer.gryonixnexus.servercontrol.QuickTransferChannel
import com.skaymer.gryonixnexus.servercontrol.QuickTransferFailure
import com.skaymer.gryonixnexus.servercontrol.QuickTransferFlow
import com.skaymer.gryonixnexus.servercontrol.QuickTransferLink
import com.skaymer.gryonixnexus.servercontrol.QuickTransferRace
import com.skaymer.gryonixnexus.servercontrol.QuickTransferTcpLink
import com.skaymer.gryonixnexus.servercontrol.QuickTransferTcpListener
import com.skaymer.gryonixnexus.servercontrol.QuickTransferTicket
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Shows the code, waits for a receiver, sends the servers */
class QuickTransferSendState(
    private val context: Context,
    val deployments: List<Deployment>,
    private val prepare: suspend (Deployment) -> String?,
    private val scope: CoroutineScope,
) {
    sealed interface Phase {
        data object Starting : Phase
        data object Showing : Phase
        data class Asking(val device: String, val code: String) : Phase
        data class Sending(val device: String) : Phase
        data class Sent(val device: String, val count: Int) : Phase
        data class Failed(val message: String) : Phase
    }

    var phase by mutableStateOf<Phase>(Phase.Starting)
        private set
    var ticket by mutableStateOf<QuickTransferTicket?>(null)
        private set
    private var listener: QuickTransferTcpListener? = null
    private var bluetooth: QuickTransferBluetoothSender? = null
    private var peer: QuickTransferChannel? = null

    /** Opens both doors and puts a fresh code on screen */
    fun start(bluetoothAllowed: Boolean) {
        closeDoors()
        peer = null
        phase = Phase.Starting
        scope.launch {
            val tcp = withContext(Dispatchers.IO) { runCatching { QuickTransferTcpListener() }.getOrNull() }
            tcp?.start(::offer)
            listener = tcp
            val addresses = if (tcp == null) emptyList() else withContext(Dispatchers.IO) { QuickTransferAddresses.current() }
            val fresh = QuickTransferTicket.fresh(tcp?.port ?: 0, addresses)
            ticket = fresh
            if (bluetoothAllowed) {
                bluetooth = QuickTransferBluetoothSender(context, fresh.bluetoothService, ::offer).also { it.start() }
            }
            phase = Phase.Showing
        }
    }

    /** A new link; only our hello gets in */
    private fun offer(link: QuickTransferLink) {
        scope.launch(Dispatchers.Main) {
            val current = ticket
            if (peer != null || current == null) return@launch link.close()
            val channel = QuickTransferChannel(link, current.key, QuickTransferChannel.Role.SENDER)
            val hello = runCatching { QuickTransferFlow.greet(channel) }.getOrNull()
            if (hello == null || peer != null) return@launch channel.close()
            peer = channel
            stopAccepting()
            phase = Phase.Asking(hello.device, hello.code)
        }
    }

    fun allow() {
        val channel = peer ?: return
        val asking = phase as? Phase.Asking ?: return
        phase = Phase.Sending(asking.device)
        scope.launch {
            phase = runCatching {
                QuickTransferFlow.accept(channel)
                val servers = deployments.mapNotNull { prepare(it) }
                if (servers.isEmpty()) throw QuickTransferFailure.Unexpected()
                Phase.Sent(asking.device, QuickTransferFlow.deliver(channel, servers))
            }.getOrElse { Phase.Failed(context.getString(R.string.quick_transfer_stopped)) }
            channel.close()
        }
    }

    /** Refuses this device and shows a new code */
    fun decline(bluetoothAllowed: Boolean) {
        peer?.let { channel -> scope.launch { QuickTransferFlow.decline(channel) } }
        start(bluetoothAllowed)
    }

    fun stop() {
        closeDoors()
        peer?.close()
        peer = null
    }

    /** Takes no one new; the chosen receiver's link stays open */
    private fun stopAccepting() {
        listener?.stop()
        listener = null
        bluetooth?.stopAdvertising()
    }

    private fun closeDoors() {
        stopAccepting()
        bluetooth?.stop()
        bluetooth = null
    }
}

/** Reads the code, reaches the sender, takes the servers in */
class QuickTransferReceiveState(
    private val context: Context,
    private val deliver: (List<String>) -> List<String>,
    private val scope: CoroutineScope,
) {
    sealed interface Phase {
        data object Scanning : Phase
        data object Connecting : Phase
        data class Confirming(val code: String) : Phase
        data object Receiving : Phase
        data class Received(val names: List<String>) : Phase
        data class Failed(val message: String) : Phase
    }

    var phase by mutableStateOf<Phase>(Phase.Scanning)
        private set
    private var job: Job? = null

    /** A scanned text; true when it is a transfer code */
    fun scanned(text: String, bluetoothAllowed: Boolean): Boolean {
        if (phase != Phase.Scanning) return false
        val ticket = QuickTransferTicket.parse(text) ?: return false
        phase = Phase.Connecting
        job = scope.launch { run(ticket, bluetoothAllowed) }
        return true
    }

    fun retry() {
        job?.cancel()
        phase = Phase.Scanning
    }

    fun stop() {
        job?.cancel()
    }

    private suspend fun run(ticket: QuickTransferTicket, bluetoothAllowed: Boolean) {
        var channel: QuickTransferChannel? = null
        try {
            val link = QuickTransferRace.first(attempts(ticket, bluetoothAllowed), 25_000)
            val open = QuickTransferChannel(link, ticket.key, QuickTransferChannel.Role.RECEIVER).also { channel = it }
            phase = Phase.Confirming(QuickTransferFlow.knock(open, deviceName()))
            QuickTransferFlow.awaitAnswer(open)
            phase = Phase.Receiving
            val texts = QuickTransferFlow.collect(open)
            phase = Phase.Received(deliver(texts))
        } catch (error: QuickTransferFailure) {
            phase = Phase.Failed(message(error))
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            phase = Phase.Failed(context.getString(R.string.quick_transfer_stopped))
        } finally {
            channel?.let { closeSoon(it) }
        }
    }

    private fun attempts(ticket: QuickTransferTicket, bluetoothAllowed: Boolean): List<suspend () -> QuickTransferLink> {
        val attempts = mutableListOf<suspend () -> QuickTransferLink>()
        if (ticket.addresses.isNotEmpty() && ticket.port != 0) {
            attempts += { QuickTransferTcpLink.connectFirst(ticket.addresses, ticket.port, 6000) }
        }
        if (bluetoothAllowed) {
            attempts += {
                delay(1500)
                QuickTransferBluetoothReceiver.connect(context, ticket.bluetoothService)
            }
        }
        return attempts
    }

    /** Lets the last reply leave before the link goes */
    private fun closeSoon(channel: QuickTransferChannel) {
        scope.launch {
            delay(500)
            channel.close()
        }
    }

    private fun message(error: QuickTransferFailure): String = context.getString(
        when (error) {
            is QuickTransferFailure.Declined -> R.string.quick_transfer_declined
            is QuickTransferFailure.NotOurs -> R.string.quick_transfer_other_code
            is QuickTransferFailure.TimedOut, is QuickTransferFailure.Closed -> R.string.quick_transfer_unreachable
            else -> R.string.quick_transfer_stopped
        },
    )

    private fun deviceName(): String =
        Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) ?: Build.MODEL
}
