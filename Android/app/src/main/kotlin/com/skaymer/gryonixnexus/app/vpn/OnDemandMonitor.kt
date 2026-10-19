package com.skaymer.gryonixnexus.app.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.catalog.ServiceID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject

/** The tunnel last started by hand */
class LastTunnel(private val secrets: SecretStore) {
    /** An empty clientId means this phone's own device */
    data class Profile(
        val device: String,
        val configuration: String,
        val protocol: ServiceID,
        val server: String,
        val serverId: String = "",
        val clientId: String = "",
        val clientName: String = "",
    )

    fun save(profile: Profile) {
        val json = JSONObject()
            .put("device", profile.device)
            .put("configuration", profile.configuration)
            .put("protocol", profile.protocol.rawValue)
            .put("server", profile.server)
            .put("serverId", profile.serverId)
            .put("clientId", profile.clientId)
            .put("clientName", profile.clientName)
        secrets.setString(ACCOUNT, json.toString())
    }

    fun load(): Profile? = runCatching {
        val json = JSONObject(secrets.string(ACCOUNT) ?: return null)
        Profile(
            json.getString("device"), json.getString("configuration"),
            ServiceID(json.getString("protocol")), json.optString("server"),
            json.optString("serverId"), json.optString("clientId"), json.optString("clientName"),
        )
    }.getOrNull()

    private companion object {
        const val ACCOUNT = "vpn.lastTunnel"
    }
}

/** Brings the tunnel up or down as networks change */
class OnDemandMonitor(
    private val context: Context,
    private val tunnel: VpnTunnel,
    private val settings: OnDemandSettings,
    private val last: LastTunnel,
    /** The profile as its server knows it now, if reachable */
    private val refresh: suspend (LastTunnel.Profile) -> LastTunnel.Profile? = { null },
) {
    private val networks = mutableMapOf<Network, NetworkCapabilities>()
    private val scope = CoroutineScope(Dispatchers.Main)

    fun start() {
        val manager = context.getSystemService(ConnectivityManager::class.java) ?: return
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()
        manager.registerNetworkCallback(request, callback())
        scope.launch { settings.policy.collect { evaluate() } }
    }

    private fun callback(): ConnectivityManager.NetworkCallback {
        val flags = if (Build.VERSION.SDK_INT >= 31) ConnectivityManager.NetworkCallback.FLAG_INCLUDE_LOCATION_INFO else 0
        return object : ConnectivityManager.NetworkCallback(flags) {
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                scope.launch { networks[network] = capabilities; evaluate() }
            }

            override fun onLost(network: Network) {
                scope.launch { networks.remove(network); evaluate() }
            }
        }
    }

    /** Wi-Fi first, as the system routes it */
    private fun current(): OnDemandPolicy.Network? {
        val all = networks.values.filterNot { it.hasTransport(NetworkCapabilities.TRANSPORT_VPN) }
        all.firstOrNull { it.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) }?.let {
            return OnDemandPolicy.Network.WiFi(ssid(it))
        }
        if (all.any { it.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) }) return OnDemandPolicy.Network.Cellular
        return if (all.isEmpty()) null else OnDemandPolicy.Network.Other
    }

    @Suppress("DEPRECATION")
    private fun ssid(capabilities: NetworkCapabilities): String? {
        val info = if (Build.VERSION.SDK_INT >= 29) capabilities.transportInfo as? WifiInfo else null
        val raw = info?.ssid ?: context.applicationContext.getSystemService(WifiManager::class.java)?.connectionInfo?.ssid
        return raw?.trim('"')?.takeUnless { it.isBlank() || it == WifiManager.UNKNOWN_SSID }
    }

    private fun evaluate() {
        val wanted = settings.policy.value.wantsTunnel(current()) ?: return
        val running = tunnel.runningDevice()
        if (wanted && running == null) {
            val stored = last.load() ?: return
            if (VpnService.prepare(context) != null) return
            scope.launch {
                val profile = runCatching { refresh(stored) }.getOrNull()?.also(last::save) ?: stored
                if (tunnel.runningDevice() != null) return@launch
                val choice = TunnelChoice(profile.serverId, profile.clientId, profile.clientName)
                tunnel.connect(profile.device, profile.configuration, profile.protocol, profile.server, false, choice)
            }
        } else if (!wanted && running != null) {
            tunnel.disconnect()
        }
    }
}
