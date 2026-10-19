package com.skaymer.gryonixnexus.app.vpn

import android.content.Context
import android.content.Intent
import android.net.VpnService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.profile.ProxyLinkConfig
import org.amnezia.awg.backend.Backend
import org.amnezia.awg.backend.GoBackend
import org.amnezia.awg.backend.Tunnel
import org.amnezia.awg.config.Config
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream

class VpnTunnel(private val context: Context) {
    private companion object {
        /** 50 ms each, 15 seconds in all */
        const val XRAY_START_POLLS = 300
    }

    /** What the tunnel is doing, for a screen to draw */
    sealed interface State {
        /** Nothing is up */
        data object Down : State

        /** Bringing up, or taking down, the named device's tunnel */
        data class Working(val device: String) : State

        /** Up, carrying the named device */
        data class Up(val device: String) : State

        data class Failed(val message: String) : State
    }

    /** What the connection notification says about the session */
    data class Session(val server: String, val protocol: ServiceID, val startedAt: Long)

    private val _state = MutableStateFlow<State>(State.Down)
    val state: StateFlow<State> = _state.asStateFlow()

    private val _session = MutableStateFlow<Session?>(null)
    val session: StateFlow<Session?> = _session.asStateFlow()

    @Volatile
    private var pending: Session? = null

    /** The connection notification on/off switch */
    var noticeSettings: VpnSessionNoticeSettings? = null

    /** Where a hand-started tunnel is kept for automatic starts */
    var lastTunnel: LastTunnel? = null

    /** Addresses dialed in place of a configuration's domain */
    var endpointPins: EndpointPinStore? = null

    /** When it comes up on its own */
    var onDemand: OnDemandSettings? = null

    private val backend: Backend by lazy { GoBackend(context) }

    private val scope = CoroutineScope(Dispatchers.Main)

    /** The tunnel object the backend keys its state by */
    private inner class DeviceTunnel(private val label: String) : Tunnel {
        override fun getName(): String = "gryonix"

        override fun onStateChange(newState: Tunnel.State) {
            when (newState) {
                Tunnel.State.UP -> markUp(label)
                Tunnel.State.DOWN -> markDown()
                Tunnel.State.TOGGLE -> _state.value = State.Working(label)
            }
        }
    }

    fun canCarry(protocol: ServiceID): Boolean = when (protocol) {
        ServiceID.WIREGUARD_VPN, ServiceID.AMNEZIA_WG -> true
        ServiceID.SHADOWSOCKS, ServiceID.XRAY_REALITY -> true
        else -> false
    }

    /** The same question with the configuration in hand */
    fun canCarry(protocol: ServiceID, configuration: String): Boolean {
        if (!canCarry(protocol)) return false
        if (protocol != ServiceID.SHADOWSOCKS && protocol != ServiceID.XRAY_REALITY) return true
        return runCatching { ProxyLinkConfig.parse(configuration) }.isSuccess
    }

    /** Which of the two datapaths carries this protocol */
    private fun isProxyProtocol(protocol: ServiceID): Boolean =
        protocol == ServiceID.SHADOWSOCKS || protocol == ServiceID.XRAY_REALITY

    fun permissionRequest(): Intent? = VpnService.prepare(context)

    /** Bring up this configuration, replacing whatever tunnel is up */
    fun connect(
        device: String,
        configuration: String,
        protocol: ServiceID = ServiceID.WIREGUARD_VPN,
        server: String = "",
        remember: Boolean = true,
        choice: TunnelChoice? = null,
    ) {
        val profile = LastTunnel.Profile(device, configuration, protocol, server,
            choice?.serverId.orEmpty(), choice?.clientId.orEmpty(), choice?.clientName.orEmpty())
        if (remember) lastTunnel?.save(profile)
        val pinned = endpointPins?.address(profile)
        val previous = runningDevice()
        pending = Session(server, protocol, 0L)
        _session.value = null
        _state.value = State.Working(device)
        scope.launch {
            if (previous != null) tearDown(previous)
            _state.value = State.Working(device)
            if (isProxyProtocol(protocol)) {
                connectThroughXray(device, configuration, pinned)
            } else {
                connectWireGuard(device, pinned?.let { EndpointPins.pinnedWireGuard(configuration, it) } ?: configuration)
            }
        }
    }

    /** The device whose tunnel is up or on its way */
    fun runningDevice(): String? = when (val current = state.value) {
        is State.Up -> current.device
        is State.Working -> current.device
        else -> null
    }

    private suspend fun connectWireGuard(device: String, configuration: String) {
        val outcome = runCatching {
            val config = withContext(Dispatchers.IO) {
                Config.parse(ByteArrayInputStream(configuration.toByteArray()))
            }
            withContext(Dispatchers.IO) {
                backend.setState(DeviceTunnel(device), Tunnel.State.UP, config)
            }
        }
        outcome.exceptionOrNull()?.let { failure ->
            _state.value = State.Failed(failure.message ?: failure.toString())
        }
    }

    private suspend fun connectThroughXray(device: String, configuration: String, pinned: String?) {
        XrayVpnService.start(context, configuration, pinned)
        repeat(XRAY_START_POLLS) {
            if (XrayVpnService.isRunning.value) {
                markUp(device)
                return
            }
            XrayVpnService.failure?.let { message ->
                _state.value = State.Failed(message)
                return
            }
            delay(50)
        }
        _state.value = State.Failed(
            XrayVpnService.failure ?: "the tunnel service did not come up",
        )
    }

    /** Take it down */
    fun disconnect() {
        val device = runningDevice()
        scope.launch {
            tearDown(device.orEmpty())
            markDown()
        }
    }

    private fun markUp(device: String) {
        _state.value = State.Up(device)
        if (_session.value == null) {
            _session.value = pending?.copy(startedAt = System.currentTimeMillis())
        }
    }

    private fun markDown() {
        _state.value = State.Down
        _session.value = null
    }

    private suspend fun tearDown(device: String) {
        XrayVpnService.stop(context)
        runCatching {
            withContext(Dispatchers.IO) {
                backend.setState(DeviceTunnel(device), Tunnel.State.DOWN, null)
            }
        }
        repeat(40) {
            if (!XrayVpnService.isRunning.value) return
            delay(50)
        }
    }
}
