package com.skaymer.gryonixnexus.app.widgets

import android.content.Context
import java.io.File
import kotlinx.serialization.json.Json

/** The snapshot file the app writes and the widgets read */
class FleetSnapshotStore(private val file: File) {
    constructor(context: Context) : this(File(context.filesDir, FILE_NAME))

    fun read(): FleetSnapshot? = synchronized(LOCK) {
        if (!file.exists()) return null
        runCatching { json.decodeFromString(FleetSnapshot.serializer(), file.readText()) }.getOrNull()
    }

    fun write(snapshot: FleetSnapshot): Boolean = synchronized(LOCK) {
        runCatching {
            val staged = File(file.parentFile, "${file.name}.new")
            staged.writeText(json.encodeToString(FleetSnapshot.serializer(), snapshot))
            staged.renameTo(file)
        }.getOrDefault(false)
    }

    /** Changes one server, adding it when missing */
    fun updateServer(id: String, name: String, change: (FleetSnapshot.Server) -> FleetSnapshot.Server): Boolean =
        edit { snapshot ->
            val current = snapshot.servers.firstOrNull { it.id == id } ?: FleetSnapshot.Server(id, name)
            val next = change(current.copy(name = name))
            val servers = if (snapshot.servers.any { it.id == id }) {
                snapshot.servers.map { if (it.id == id) next else it }
            } else {
                snapshot.servers + next
            }
            snapshot.copy(servers = servers, generatedAt = System.currentTimeMillis())
        }

    /** One protocol's devices, or why the server did not answer */
    fun upsertProtocol(id: String, name: String, reading: FleetSnapshot.ProtocolDevices?, failure: String?): Boolean =
        updateServer(id, name) { server ->
            val protocols = reading?.let { fresh ->
                (server.protocols.filter { it.protocolID != fresh.protocolID } + fresh).sortedBy { it.protocolID }
            } ?: server.protocols
            server.copy(protocols = protocols, failure = failure)
        }

    fun writeTunnel(tunnel: TunnelSnapshot): Boolean = edit { it.copy(tunnel = tunnel) }

    fun forgetServer(id: String): Boolean = edit { snapshot ->
        snapshot.copy(servers = snapshot.servers.filter { it.id != id })
    }

    private fun edit(change: (FleetSnapshot) -> FleetSnapshot): Boolean = synchronized(LOCK) {
        val before = read() ?: FleetSnapshot()
        val after = change(before)
        after == before || write(after)
    }

    companion object {
        const val FILE_NAME = "fleet-snapshot.json"
        private val LOCK = Any()
        private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    }
}
