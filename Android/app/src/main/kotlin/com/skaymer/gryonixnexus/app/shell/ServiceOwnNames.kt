package com.skaymer.gryonixnexus.app.shell

import com.skaymer.gryonixnexus.catalog.ManagedService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Names given to services, by server */
class ServiceOwnNames(private val store: SettingsStore) {
    private val _servers = MutableStateFlow(read())
    /** Names of each server, by service id */
    val servers: StateFlow<Map<String, Map<String, String>>> = _servers.asStateFlow()

    fun names(server: String): Map<String, String> = _servers.value[server].orEmpty()

    /** The given name, or the catalog one */
    fun title(service: ManagedService, server: String): String =
        _servers.value[server]?.get(service.id.rawValue) ?: service.displayName

    /** Servers whose names the agent has not taken */
    val unsent: Set<String> get() = store.stringList(UNSENT_KEY).orEmpty().toSet()

    /** Takes the server's own set as the truth */
    fun adopt(server: String, names: Map<String, String>) {
        if (server in unsent) store.setStringList(UNSENT_KEY, (unsent - server).sorted())
        val kept = names.filterValues { it.isNotEmpty() }
        if (names(server) == kept) return
        write(if (kept.isEmpty()) _servers.value - server else _servers.value + (server to kept))
    }

    /** Names a service here; empty puts the catalog name back */
    fun set(name: String, service: String, server: String, sent: Boolean) {
        val cleaned = cleaned(name)
        val names = if (cleaned.isEmpty()) names(server) - service else names(server) + (service to cleaned)
        write(if (names.isEmpty()) _servers.value - server else _servers.value + (server to names))
        if (!sent) store.setStringList(UNSENT_KEY, (unsent + server).sorted())
    }

    private fun write(all: Map<String, Map<String, String>>) {
        store.setStringList(NAMES_KEY, all.flatMap { (server, names) -> names.map { (id, name) -> "$server\t$id\t$name" } })
        _servers.value = all
    }

    private fun read(): Map<String, Map<String, String>> =
        store.stringList(NAMES_KEY).orEmpty()
            .mapNotNull { line -> line.split('\t', limit = 3).takeIf { it.size == 3 } }
            .groupBy({ it[0] }, { it[1] to it[2] })
            .mapValues { (_, pairs) -> pairs.toMap() }

    companion object {
        const val NAMES_KEY = "serviceNames.byServer"
        const val UNSENT_KEY = "serviceNames.unsent"
        const val MAX_LENGTH = 60

        fun cleaned(name: String): String =
            name.map { if (it.isISOControl()) ' ' else it }.joinToString("").trim().take(MAX_LENGTH).trim()
    }
}
