package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.app.shell.SettingsStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** When this device's tunnel comes up on its own */
data class OnDemandPolicy(
    val isEnabled: Boolean = false,
    val scope: Scope = Scope.ANY,
    val mode: NetworkMode = NetworkMode.EXCEPT_LISTED,
    val networks: List<String> = emptyList(),
) {
    enum class Scope { ANY, WIFI, CELLULAR }

    /** How the listed Wi-Fi networks are read */
    enum class NetworkMode { EXCEPT_LISTED, ONLY_LISTED }

    sealed interface Network {
        /** A Wi-Fi network; its name when the system tells it */
        data class WiFi(val ssid: String?) : Network
        data object Cellular : Network
        data object Other : Network
    }

    /** Up, down, or null to leave the tunnel alone */
    fun wantsTunnel(network: Network?): Boolean? {
        if (!isEnabled || network == null) return null
        return when (network) {
            is Network.WiFi -> scope != Scope.CELLULAR && wantsWiFi(network.ssid)
            Network.Cellular -> scope != Scope.WIFI
            Network.Other -> if (scope == Scope.ANY) true else null
        }
    }

    private fun wantsWiFi(ssid: String?): Boolean {
        val listed = networks.filter { it.isNotBlank() }
        if (listed.isEmpty()) return true
        val known = ssid != null && listed.any { it.trim().equals(ssid, ignoreCase = true) }
        return when (mode) {
            NetworkMode.EXCEPT_LISTED -> !known
            NetworkMode.ONLY_LISTED -> known
        }
    }
}

/** The stored policy, changed from the VPN screen */
class OnDemandSettings(private val store: SettingsStore) {
    private val _policy = MutableStateFlow(load())
    val policy: StateFlow<OnDemandPolicy> = _policy.asStateFlow()

    fun update(change: (OnDemandPolicy) -> OnDemandPolicy) {
        val next = change(_policy.value)
        store.setBoolean(ENABLED, next.isEnabled)
        store.setString(SCOPE, next.scope.name)
        store.setString(MODE, next.mode.name)
        store.setStringList(NETWORKS, next.networks)
        _policy.value = next
    }

    /** Adds a Wi-Fi name once, ignoring case */
    fun addNetwork(name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        update { policy ->
            if (policy.networks.any { it.equals(trimmed, ignoreCase = true) }) policy
            else policy.copy(networks = policy.networks + trimmed)
        }
    }

    fun removeNetwork(name: String) = update { it.copy(networks = it.networks - name) }

    private fun load() = OnDemandPolicy(
        isEnabled = store.boolean(ENABLED) ?: false,
        scope = store.string(SCOPE)?.let { runCatching { OnDemandPolicy.Scope.valueOf(it) }.getOrNull() }
            ?: OnDemandPolicy.Scope.ANY,
        mode = store.string(MODE)?.let { runCatching { OnDemandPolicy.NetworkMode.valueOf(it) }.getOrNull() }
            ?: OnDemandPolicy.NetworkMode.EXCEPT_LISTED,
        networks = store.stringList(NETWORKS).orEmpty(),
    )

    private companion object {
        const val ENABLED = "vpn.onDemand.enabled"
        const val SCOPE = "vpn.onDemand.scope"
        const val MODE = "vpn.onDemand.mode"
        const val NETWORKS = "vpn.onDemand.networks"
    }
}
