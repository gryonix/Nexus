package com.skaymer.gryonixnexus.app.vpn

import android.content.SharedPreferences
import java.net.InetAddress
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** Endpoint pins kept on this device, one per tunnel */
class EndpointPinStore(private val preferences: SharedPreferences) {
    fun pin(key: String): EndpointPin? = runCatching {
        val json = JSONObject(preferences.getString(key, null) ?: return null)
        EndpointPin(json.getString("host"), json.getString("address"))
    }.getOrNull()

    fun save(key: String, pin: EndpointPin) {
        val json = JSONObject().put("host", pin.host).put("address", pin.address)
        preferences.edit().putString(key, json.toString()).apply()
    }

    fun remove(key: String) {
        preferences.edit().remove(key).apply()
    }

    /** The profile's pin, when it still fits its configuration */
    fun address(profile: LastTunnel.Profile): String? =
        EndpointPins.address(pin(EndpointPins.key(profile)), profile.protocol, endpoint(profile))

    /** The `IP:port` the profile dials while pinned */
    fun pinnedEndpoint(profile: LastTunnel.Profile): String? =
        EndpointPins.pinnedEndpoint(pin(EndpointPins.key(profile)), profile.protocol, endpoint(profile))

    private fun endpoint(profile: LastTunnel.Profile): String? =
        EndpointPins.endpoint(profile.protocol, profile.configuration)

    companion object {
        const val FILE = "vpn.endpointPins"

        /** Looks the domain up now, off the main thread */
        suspend fun lookUp(host: String): PinOutcome = withContext(Dispatchers.IO) {
            val answers = runCatching {
                InetAddress.getAllByName(host).mapNotNull { it.hostAddress?.substringBefore('%') }
            }.getOrDefault(emptyList())
            EndpointPins.outcome(host, answers)
        }
    }
}
