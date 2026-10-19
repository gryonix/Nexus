package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.catalog.ServiceID
import gryonixnexusd.v1.ModFileList
import gryonixnexusd.v1.ModSearchResult
import gryonixnexusd.v1.ModSlot
import gryonixnexusd.v1.ModVersion

class AgentModOperations(
    private val client: AgentClient,
    private val gate: AgentChannelGate? = null,
) {
    suspend fun search(
        query: String,
        gameVersion: String,
        loader: String,
        limit: Int = 0,
        offset: Int = 0,
    ): ModSearchResult =
        mapping { client.searchMods(SERVICE_ID, query, gameVersion, loader, limit, offset) }

    suspend fun versions(project: String, gameVersion: String, loader: String): List<ModVersion> =
        mapping { client.modVersions(SERVICE_ID, project, gameVersion, loader).versions }

    suspend fun files(): ModFileList = mapping { client.listModFiles(SERVICE_ID) }

    suspend fun upload(name: String, slot: ModSlot, content: ByteArray): ModFileList =
        mapping { client.uploadModFile(SERVICE_ID, slot, name, content) }

    suspend fun delete(name: String, slot: ModSlot): ModFileList =
        mapping { client.deleteModFile(SERVICE_ID, slot, name) }

    private suspend fun <T> mapping(body: suspend () -> T): T =
        agentFailure("mods") { gate.gated(body) }

    companion object {
        /** The one service that takes mods today */
        val SERVICE_ID: String = ServiceID.MINECRAFT_JAVA.rawValue

        fun loader(forFlavour: String): String? = when (forFlavour.uppercase()) {
            "FABRIC" -> "fabric"
            "FORGE" -> "forge"
            "NEOFORGE" -> "neoforge"
            "QUILT" -> "quilt"
            "PAPER" -> "paper"
            "PURPUR" -> "purpur"
            "SPIGOT" -> "spigot"
            "BUKKIT" -> "bukkit"
            else -> null
        }

        fun slot(forFlavour: String): ModSlot = when (forFlavour.uppercase()) {
            "PAPER", "PURPUR", "SPIGOT", "BUKKIT" -> ModSlot.MOD_SLOT_PLUGINS
            else -> ModSlot.MOD_SLOT_MODS
        }

        fun entry(slug: String, versionID: String): String =
            if (versionID.isEmpty()) slug else "$slug:$versionID"

        /** The stored list, as a list */
        fun entries(setting: String): List<String> =
            setting.split(",").map { it.trim() }.filter { it.isNotEmpty() }

        /** The setting text for a list of entries */
        fun setting(entries: List<String>): String =
            entries.map { it.trim() }.filter { it.isNotEmpty() }.joinToString(",")

        fun slug(ofEntry: String): String = ofEntry.split(":").firstOrNull() ?: ""
    }
}
