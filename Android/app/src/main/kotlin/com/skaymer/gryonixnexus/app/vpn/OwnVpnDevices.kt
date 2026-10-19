package com.skaymer.gryonixnexus.app.vpn

import android.content.SharedPreferences

/** This phone's own server-side device, per server and protocol */
interface OwnVpnDevices {
    fun clientId(serverId: String, protocol: String): String?
    fun remember(serverId: String, protocol: String, clientId: String)

    companion object {
        fun inMemory(): OwnVpnDevices = object : OwnVpnDevices {
            private val ids = mutableMapOf<String, String>()
            override fun clientId(serverId: String, protocol: String) = ids["$serverId/$protocol"]
            override fun remember(serverId: String, protocol: String, clientId: String) {
                ids["$serverId/$protocol"] = clientId
            }
        }

        fun stored(preferences: SharedPreferences): OwnVpnDevices = object : OwnVpnDevices {
            override fun clientId(serverId: String, protocol: String) =
                preferences.getString("vpn.own.$serverId.$protocol", null)

            override fun remember(serverId: String, protocol: String, clientId: String) {
                preferences.edit().putString("vpn.own.$serverId.$protocol", clientId).apply()
            }
        }
    }
}
