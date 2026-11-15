package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.catalog.ServiceID
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Tunnels imported from servers the app does not manage */
class ImportedTunnels(private val secrets: SecretStore) {
    @Serializable
    data class Entry(val id: String, val name: String, val protocol: String, val text: String) {
        val protocolID: ServiceID get() = ServiceID(protocol)

        /** The server id a chosen tunnel carries */
        val serverId: String get() = PREFIX + id
    }

    fun all(): List<Entry> = runCatching {
        Json.decodeFromString<List<Entry>>(secrets.string(ACCOUNT) ?: return emptyList())
    }.getOrDefault(emptyList())

    fun add(detected: ForeignTunnelConfig.Detected, name: String): Entry {
        val entry = Entry(UUID.randomUUID().toString(), name.trim().ifEmpty { detected.suggestedName },
            detected.protocol.rawValue, detected.text)
        save(all() + entry)
        return entry
    }

    fun remove(id: String) = save(all().filterNot { it.id == id })

    private fun save(entries: List<Entry>) = secrets.setString(ACCOUNT, Json.encodeToString(entries))

    companion object {
        const val PREFIX = "imported:"
        const val CLIENT = "imported"
        private const val ACCOUNT = "vpn.imported"

        /** Resolvers for an imported link, which names none */
        val PROXY_DNS = listOf("1.1.1.1", "1.0.0.1")

        fun isImported(serverId: String): Boolean = serverId.startsWith(PREFIX)
    }
}
