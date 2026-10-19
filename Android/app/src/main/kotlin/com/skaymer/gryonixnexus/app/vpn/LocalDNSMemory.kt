package com.skaymer.gryonixnexus.app.vpn

import android.content.SharedPreferences
import com.skaymer.gryonixnexus.agentcontrol.VPNDNSDefaults
import com.skaymer.gryonixnexus.catalog.ServiceID

/** The last resolver each server offered, kept across launches */
class LocalDNSMemory(
    private val read: (String) -> String?,
    private val write: (String, String) -> Unit,
) {
    fun recall(serverId: String): VPNDNSDefaults? {
        val saved = read(key(serverId))?.split('|')?.filter { it.isNotEmpty() } ?: return null
        val address = saved.firstOrNull() ?: return null
        return VPNDNSDefaults(localAddress = address, localServices = saved.drop(1).map { ServiceID(it) })
    }

    fun keep(serverId: String, defaults: VPNDNSDefaults) {
        if (!LocalDNS(defaults.localAddress, defaults.localServices).isOffered) return
        write(key(serverId), (listOf(defaults.localAddress) + defaults.localServices.map { it.rawValue }).joinToString("|"))
    }

    private fun key(serverId: String) = "vpn.localDNS.$serverId"

    companion object {
        fun inMemory(): LocalDNSMemory {
            val saved = mutableMapOf<String, String>()
            return LocalDNSMemory({ saved[it] }, { key, value -> saved[key] = value })
        }

        fun stored(preferences: SharedPreferences) = LocalDNSMemory(
            { preferences.getString(it, null) },
            { key, value -> preferences.edit().putString(key, value).apply() },
        )
    }
}
