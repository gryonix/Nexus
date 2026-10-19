package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.agentcontrol.VPNClientConfiguration
import com.skaymer.gryonixnexus.agentcontrol.VPNClientDevice
import com.skaymer.gryonixnexus.agentcontrol.VPNDNSDefaults
import com.skaymer.gryonixnexus.agentcontrol.VPNDNSPriority
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import com.skaymer.gryonixnexus.app.licensing.LicensePrompt

/** What the devices screen is showing for one protocol */
data class VPNClientsState(
    val protocol: ServiceID? = null,
    val devices: List<VPNClientDevice> = emptyList(),
    val isBusy: Boolean = false,
    val errorMessage: String? = null,
    val notice: String? = null,
    val hasAnswered: Boolean = false,
    /** The DNS new devices get, and the server's own resolver */
    val dnsDefaults: VPNDNSDefaults = VPNDNSDefaults(),
    /** The DNS relay's resolver order, when the agent keeps one */
    val dnsPriority: VPNDNSPriority? = null,
) {
    val defaultDNS: List<String> get() = dnsDefaults.dns

    val localDNS: LocalDNS get() = LocalDNS(dnsDefaults.localAddress, dnsDefaults.localServices)

    /** Whether the screen may say "this server has no devices" */
    val saysThereAreNone: Boolean
        get() = hasAnswered && devices.isEmpty() && !isBusy && errorMessage == null
}

/** The client devices of one server's VPN, over the agent */
data class VPNClientNotices(
    val added: String = "The device was added.",
    val removed: String = "The device was removed.",
    val dnsChanged: String = "The device's DNS was changed.",
)

class VPNClientsViewModel(
    private val scope: CoroutineScope,
    private val operations: suspend (Deployment) -> VPNClientManaging,
    private val release: suspend (Deployment) -> Unit = {},
    private val ownDevices: OwnVpnDevices = OwnVpnDevices.inMemory(),
    private val notices: VPNClientNotices = VPNClientNotices(),
    private val localMemory: LocalDNSMemory = LocalDNSMemory.inMemory(),
) {
    private val _state = MutableStateFlow(VPNClientsState())
    val state: StateFlow<VPNClientsState> = _state.asStateFlow()

    private var job: Job? = null

    /** Show this protocol's devices */
    fun load(deployment: Deployment, protocol: ServiceID) {
        job?.cancel()
        val switching = _state.value.protocol != protocol
        _state.value =
            if (switching) {
                VPNClientsState(
                    protocol = protocol,
                    isBusy = true,
                    dnsDefaults = _state.value.dnsDefaults,
                    dnsPriority = _state.value.dnsPriority,
                )
            }
            else _state.value.copy(isBusy = true, errorMessage = null)
        job = scope.launch {
            run(deployment) { it.list(protocol) }
        }
    }

    fun add(deployment: Deployment, protocol: ServiceID, name: String, dns: List<String> = emptyList()) {
        if (!LicensePrompt.allow()) return
        job?.cancel()
        _state.value = _state.value.copy(isBusy = true, errorMessage = null, notice = null)
        job = scope.launch {
            run(deployment, notice = notices.added) { it.add(protocol, name, dns) }
        }
    }

    fun setDNS(deployment: Deployment, protocol: ServiceID, clientID: String, dns: List<String>) {
        job?.cancel()
        _state.value = _state.value.copy(isBusy = true, errorMessage = null, notice = null)
        job = scope.launch {
            run(deployment, notice = notices.dnsChanged) { it.setDNS(protocol, clientID, dns) }
        }
    }

    fun loadDefaultDNS(deployment: Deployment) {
        scope.launch {
            val loaded = runCatching { operations(deployment).defaultDNS() }.getOrNull() ?: return@launch
            _state.value = _state.value.copy(dnsDefaults = VPNRelayRouting.withHomeResolvers(deployment, loaded))
        }
    }

    fun setDefaultDNS(deployment: Deployment, dns: List<String>) {
        scope.launch {
            try {
                val saved = operations(deployment).setDefaultDNS(dns)
                _state.value = _state.value.copy(dnsDefaults = VPNRelayRouting.withHomeResolvers(deployment, saved))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                _state.value = _state.value.copy(errorMessage = reason(failure))
            }
        }
    }

    fun loadDNSPriority(deployment: Deployment) {
        scope.launch {
            val loaded = try {
                operations(deployment).dnsPriority()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                null
            }
            _state.value = _state.value.copy(dnsPriority = loaded)
        }
    }

    fun setDNSPriority(deployment: Deployment, resolvers: List<String>) {
        scope.launch {
            try {
                _state.value = _state.value.copy(dnsPriority = operations(deployment).setDNSPriority(resolvers))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                _state.value = _state.value.copy(errorMessage = reason(failure))
            }
        }
    }

    fun remove(deployment: Deployment, protocol: ServiceID, clientID: String) {
        job?.cancel()
        _state.value = _state.value.copy(isBusy = true, errorMessage = null, notice = null)
        job = scope.launch {
            run(deployment, notice = notices.removed) { it.remove(protocol, clientID) }
        }
    }

    /** One device's configuration, for showing and copying */
    suspend fun configuration(
        deployment: Deployment,
        protocol: ServiceID,
        clientID: String,
    ): VPNClientConfiguration? = if (!LicensePrompt.allow()) null else try {
        operations(deployment).configuration(protocol, clientID)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        release(deployment)
        _state.value = _state.value.copy(errorMessage = reason(failure))
        null
    }

    /** This phone's own device on the server, created if missing */
    suspend fun thisDeviceConfiguration(
        deployment: Deployment,
        protocol: ServiceID,
        label: String,
        dns: List<String> = emptyList(),
    ): VPNClientConfiguration? = if (!LicensePrompt.allow()) null else try {
        val operations = operations(deployment)
        val known = operations.list(protocol).toList()
        val knownIds = known.map { it.id }.toSet()
        val remembered = ownDevices.clientId(deployment.id, protocol.rawValue)
        val device = known.firstOrNull { it.id == remembered }
            ?: operations.add(protocol, label, dns).firstOrNull { it.id !in knownIds }
        device?.let { ownDevices.remember(deployment.id, protocol.rawValue, it.id) }
        if (device != null && dns.isNotEmpty() && device.dns != dns) operations.setDNS(protocol, device.id, dns)
        _state.value = _state.value.copy(devices = operations.list(protocol), hasAnswered = true)
        device?.let { operations.configuration(protocol, it.id) }
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        release(deployment)
        _state.value = _state.value.copy(errorMessage = reason(failure))
        null
    }

    /** One protocol's devices, leaving what the screen shows alone */
    suspend fun devicesOf(deployment: Deployment, protocol: ServiceID): List<VPNClientDevice> = try {
        operations(deployment).list(protocol)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        release(deployment)
        emptyList()
    }

    /** A server's DNS defaults, leaving what the screen shows alone */
    suspend fun dnsDefaultsOf(deployment: Deployment): VPNDNSDefaults? = try {
        VPNRelayRouting.withHomeResolvers(deployment, operations(deployment).defaultDNS())
            .also { localMemory.keep(deployment.id, it) }
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        release(deployment)
        localMemory.recall(deployment.id)
    }

    /** Changes one device's DNS and reads its new configuration */
    suspend fun changeDNS(
        deployment: Deployment,
        protocol: ServiceID,
        clientID: String,
        dns: List<String>,
    ): VPNClientConfiguration? = try {
        val operations = operations(deployment)
        operations.setDNS(protocol, clientID, dns)
        operations.configuration(protocol, clientID)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        release(deployment)
        _state.value = _state.value.copy(errorMessage = reason(failure))
        null
    }

    /** The id of this phone's own server device */
    fun ownClientId(deployment: Deployment, protocol: ServiceID): String? =
        ownDevices.clientId(deployment.id, protocol.rawValue)

    fun stop() {
        job?.cancel()
        job = null
    }

    fun clearNotice() {
        _state.value = _state.value.copy(notice = null)
    }

    private suspend fun run(
        deployment: Deployment,
        notice: String? = null,
        body: suspend (VPNClientManaging) -> List<VPNClientDevice>,
    ) {
        try {
            val devices = body(operations(deployment))
            _state.value = _state.value.copy(
                devices = devices,
                isBusy = false,
                errorMessage = null,
                notice = notice,
                hasAnswered = true,
            )
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            release(deployment)
            _state.value = _state.value.copy(
                isBusy = false,
                errorMessage = reason(failure),
                hasAnswered = true,
            )
        }
    }

    private fun reason(failure: Exception): String =
        failure.message ?: failure::class.simpleName.orEmpty()
}
