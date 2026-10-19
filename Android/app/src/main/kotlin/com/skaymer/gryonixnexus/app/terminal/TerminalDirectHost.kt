package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.util.UUID

/** A machine this app never set up, reachable anyway */
@Serializable
data class TerminalDirectHost(
    val id: String = UUID.randomUUID().toString(),
    /** What the list shows */
    val name: String = "",
    val host: String,
    val port: Int = 22,
    /** The account this connection signs in as */
    val username: String,
) {
    /** The name, or the address when there is no name */
    val title: String get() = name.trim().ifEmpty { host }

    val deployment: Deployment
        get() = Deployment(
            id = id,
            name = title,
            topology = Topology.SINGLE_HOST,
            entry = HostEndpoint(host = host, port = port, user = username),
        )
}

/** The saved direct hosts, in a plain JSON file */
class TerminalDirectHostStore(private val file: File) {
    fun load(): List<TerminalDirectHost> {
        if (!file.exists()) return emptyList()
        return runCatching {
            json.decodeFromString<List<TerminalDirectHost>>(file.readText())
        }.getOrDefault(emptyList())
    }

    fun upsert(host: TerminalDirectHost) {
        val hosts = load()
        val index = hosts.indexOfFirst { it.id == host.id }
        write(if (index < 0) hosts + host else hosts.toMutableList().also { it[index] = host })
    }

    fun remove(id: String) = write(load().filterNot { it.id == id })

    private fun write(hosts: List<TerminalDirectHost>) {
        runCatching {
            file.parentFile?.mkdirs()
            file.writeText(json.encodeToString(hosts))
        }
    }

    private companion object {
        val json = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
        }
    }
}
