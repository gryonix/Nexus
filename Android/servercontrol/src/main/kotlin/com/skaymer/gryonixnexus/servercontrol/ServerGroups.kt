package com.skaymer.gryonixnexus.servercontrol

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

object ServerGroups {
    /** Where the strip's group order is kept */
    const val ORDER_KEY = "servers.groupOrder"

    fun known(deployments: List<Deployment>, order: List<String> = emptyList()): List<String> =
        ordered(deployments.flatMap { it.tags }.toSet().toList(), order)

    fun setting(member: Boolean, group: String, tags: List<String>): List<String> {
        val result = tags.filterNot { it.equals(group, ignoreCase = true) }
        return if (member) result + group else result
    }

    /** Every server that carries this group */
    fun members(group: String, deployments: List<Deployment>): List<Deployment> =
        deployments.filter { deployment ->
            deployment.tags.any { it.equals(group, ignoreCase = true) }
        }

    /** Servers in any of these groups, each once */
    fun membersOfAny(groups: List<String>, deployments: List<Deployment>): List<Deployment> =
        deployments.filter { deployment -> deployment.tags.any { contains(groups, it) } }

    fun clean(raw: String): String? = raw.trim().ifEmpty { null }

    fun reachable(selection: String?, deployments: List<Deployment>): String? =
        if (selection == null || known(deployments).contains(selection)) selection else null

    /** Placed groups first, in order, then the rest by name */
    fun ordered(groups: List<String>, order: List<String>): List<String> =
        groups.sortedWith(
            compareBy<String> { index(it, order) ?: Int.MAX_VALUE }.thenBy { it },
        )

    fun parse(raw: String?): List<String> = raw.orEmpty().split("\n").filter { it.isNotEmpty() }

    fun format(order: List<String>): String = order.joinToString("\n")

    /** The order after moving one group a place along */
    fun moving(group: String, offset: Int, among: List<String>, stored: List<String>): List<String>? {
        val order = ordered(among, stored).toMutableList()
        val from = index(group, order) ?: return null
        val to = from + offset
        if (to !in order.indices) return null
        order[from] = order[to].also { order[to] = order[from] }
        return order + stored.filterNot { contains(order, it) }
    }

    fun renaming(old: String, new: String, stored: List<String>): List<String> =
        stored.map { if (it.equals(old, ignoreCase = true)) new else it }

    fun removing(group: String, stored: List<String>): List<String> =
        stored.filterNot { it.equals(group, ignoreCase = true) }

    /** Groups new to this device join at the end */
    fun adopting(incoming: List<String>, stored: List<String>): List<String> =
        stored + incoming.filterNot { contains(stored, it) }

    private fun index(group: String, order: List<String>): Int? =
        order.indexOfFirst { it.equals(group, ignoreCase = true) }.takeIf { it >= 0 }

    private fun contains(groups: List<String>, group: String) = index(group, groups) != null
}

/** Groups and their servers, in one file Apple reads too */
@Serializable
data class ServerGroupBundle(
    val kind: String = KIND,
    val version: Int = CURRENT_VERSION,
    /** Group names, in the exporting device's order */
    val groups: List<String>,
    /** One server transfer each, as the transfer format writes it */
    val servers: List<JsonElement>,
) {
    class UnsupportedVersion : Exception("this file was exported by a newer version of the app")

    fun encoded(): String = json.encodeToString(serializer(), this)

    companion object {
        const val KIND = "gryonixgroups"
        const val CURRENT_VERSION = 1
        /** The newest server transfer this build reads */
        const val SERVER_VERSION = 1

        private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; prettyPrint = true }

        /** True for a group file, false for a single server */
        fun isBundle(text: String): Boolean = runCatching {
            json.parseToJsonElement(text).jsonObject["kind"]?.jsonPrimitive?.contentOrNull == KIND
        }.getOrDefault(false)

        fun decode(text: String): ServerGroupBundle {
            val bundle = json.decodeFromString(serializer(), text)
            val newer = bundle.servers.any { server ->
                ((server as? JsonObject)?.get("version") as? JsonPrimitive)?.intOrNull?.let { it > SERVER_VERSION } == true
            }
            if (bundle.version > CURRENT_VERSION || newer) throw UnsupportedVersion()
            return bundle
        }

        /** Each server keeps only the groups this file carries */
        fun make(groups: List<String>, servers: List<JsonElement>): ServerGroupBundle =
            ServerGroupBundle(groups = groups, servers = servers.map { trimmed(it, groups) })

        private fun trimmed(server: JsonElement, groups: List<String>): JsonElement {
            val transfer = server as? JsonObject ?: return server
            val deployment = transfer["deployment"] as? JsonObject ?: return server
            val tags = (deployment["tags"] as? JsonArray).orEmpty()
                .mapNotNull { (it as? JsonPrimitive)?.contentOrNull }
                .filter { tag -> groups.any { it.equals(tag, ignoreCase = true) } }
            val kept = JsonObject(deployment + ("tags" to JsonArray(tags.map(::JsonPrimitive))))
            return JsonObject(transfer + ("deployment" to kept))
        }

        fun fileName(groups: List<String>, several: String): String {
            val base = (if (groups.size == 1) groups.first() else several).replace("/", "-")
            return "${base.ifEmpty { "groups" }}.$FILE_EXTENSION"
        }

        const val FILE_EXTENSION = "gryonixserver"
    }
}
