package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.app.shell.SettingsStore
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Agent updates still running, kept across app launches */
class PendingAgentUpdates(
    private val store: SettingsStore?,
    private val now: () -> Long = System::currentTimeMillis,
) {
    @Serializable
    data class Entry(
        val deploymentID: String,
        val installed: String,
        val target: String,
        val published: Boolean,
        val startedAtMillis: Long,
    )

    fun load(): List<Entry> {
        val raw = store?.string(KEY) ?: return emptyList()
        val entries = runCatching { json.decodeFromString<List<Entry>>(raw) }.getOrDefault(emptyList())
        return entries.filter { now() - it.startedAtMillis < KEPT_FOR_MILLIS }
    }

    fun add(entries: List<Entry>) {
        val fresh = entries.map { it.deploymentID }.toSet()
        save(load().filterNot { it.deploymentID in fresh } + entries)
    }

    fun remove(deploymentID: String) = save(load().filterNot { it.deploymentID == deploymentID })

    /** Forgets servers that are gone */
    fun keep(deploymentIDs: Set<String>) = save(load().filter { it.deploymentID in deploymentIDs })

    fun entry(server: AgentUpdateOffer.Outdated) = Entry(
        deploymentID = server.deployment.id,
        installed = server.installed,
        target = server.target,
        published = server.source == AgentUpdateOffer.Source.PUBLISHED,
        startedAtMillis = now(),
    )

    private fun save(entries: List<Entry>) {
        val store = store ?: return
        if (entries.isEmpty()) store.remove(KEY) else store.setString(KEY, json.encodeToString(entries))
    }

    companion object {
        const val KEY = "agentUpdate.pending"
        /** Older than this, the update is given up on */
        const val KEPT_FOR_MILLIS: Long = 6 * 3_600_000L
        private val json = Json { ignoreUnknownKeys = true }
    }
}
