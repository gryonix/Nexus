package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.servercontrol.ServerAccessOptions
import kotlinx.serialization.json.Json

/** Where [ServerAccessOptions] live: this device's preferences, keyed by deployment */
object ServerAccessStore {
    private const val PREFIX = "server-access-"
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    private fun key(deploymentID: String) = PREFIX + deploymentID

    /** What this device knows about reaching that server */
    fun options(store: SettingsStore, deploymentID: String): ServerAccessOptions {
        val text = store.string(key(deploymentID)) ?: return ServerAccessOptions.NONE
        return runCatching {
            json.decodeFromString(ServerAccessOptions.serializer(), text)
        }.getOrDefault(ServerAccessOptions.NONE)
    }

    fun save(store: SettingsStore, deploymentID: String, options: ServerAccessOptions) {
        if (options.isEmpty) {
            store.remove(key(deploymentID))
            return
        }
        store.setString(key(deploymentID), json.encodeToString(ServerAccessOptions.serializer(), options))
    }

    /** Forget a server's route along with the server */
    fun forget(store: SettingsStore, deploymentID: String) = store.remove(key(deploymentID))
}
