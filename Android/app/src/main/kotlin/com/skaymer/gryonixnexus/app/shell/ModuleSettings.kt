package com.skaymer.gryonixnexus.app.shell

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class AppModule(val id: String, val onByDefault: Boolean = false) {
    AI("ai"),
    VPN_ADVANCED("vpnAdvanced"),
    PORT_FORWARDING("portForwarding"),
    SCRIPTS("scripts"),
    DOCKER_ADVANCED("dockerAdvanced"),
}

class ModuleSettings(private val store: SettingsStore) {
    private val _servers = MutableStateFlow(readServers())
    /** Last known set of each server, by deployment id */
    val servers: StateFlow<Map<String, Set<String>>> = _servers.asStateFlow()

    private val _kept = MutableStateFlow(keptNow())
    /** Modules are kept on each server's agent */
    val keptOnServers: StateFlow<Boolean> = _kept.asStateFlow()

    private val _on = MutableStateFlow(effective())
    /** On here, or on any server when kept there */
    val on: StateFlow<Set<AppModule>> = _on.asStateFlow()

    fun isOn(module: AppModule): Boolean = module in _on.value

    fun isOn(id: String): Boolean = AppModule.entries.firstOrNull { it.id == id }?.let(::isOn) ?: true

    /** On for this server */
    fun isOn(module: AppModule, server: String): Boolean =
        if (_kept.value) _servers.value[server]?.contains(module.id) == true else localIsOn(module)

    fun localIsOn(module: AppModule): Boolean = store.boolean(key(module)) ?: module.onByDefault

    fun setKeptOnServers(kept: Boolean) {
        store.setBoolean(SERVER_SYNC_KEY, kept)
        _kept.value = kept
        _on.value = effective()
    }

    /** Turns a module on or off on this device */
    fun set(module: AppModule, enabled: Boolean) {
        store.setBoolean(key(module), enabled)
        _kept.value = keptNow()
        _on.value = effective()
    }

    fun set(module: AppModule, enabled: Boolean, server: String): Set<String> {
        val current = _servers.value[server].orEmpty()
        val next = if (enabled) current + module.id else current - module.id
        adopt(server, next)
        return next
    }

    fun adopt(server: String, on: Set<String>) {
        if (_servers.value[server] == on) return
        writeServers(_servers.value + (server to on))
    }

    fun forget(server: String) {
        if (server !in _servers.value) return
        writeServers(_servers.value - server)
    }

    private fun keptNow(): Boolean = store.boolean(SERVER_SYNC_KEY) ?: AppModule.entries.none { localIsOn(it) }

    private fun writeServers(sets: Map<String, Set<String>>) {
        store.setStringList(SERVER_SETS_KEY, sets.map { (id, on) -> "$id=${on.sorted().joinToString(",")}" })
        _servers.value = sets
        _on.value = effective()
    }

    private fun readServers(): Map<String, Set<String>> =
        store.stringList(SERVER_SETS_KEY).orEmpty().mapNotNull { line ->
            val (id, list) = line.split('=', limit = 2).takeIf { it.size == 2 } ?: return@mapNotNull null
            id to list.split(',').filter { it.isNotEmpty() }.toSet()
        }.toMap()

    private fun effective(): Set<AppModule> =
        if (_kept.value) AppModule.entries.filter { m -> _servers.value.values.any { m.id in it } }.toSet()
        else AppModule.entries.filter { localIsOn(it) }.toSet()

    companion object {
        const val SERVER_SYNC_KEY = "modules.serverSync"
        const val SERVER_SETS_KEY = "modules.serverSets"
        fun key(module: AppModule): String = "modules.${module.id}"
    }
}
