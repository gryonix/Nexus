package com.skaymer.gryonixnexus.servercontrol

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Settings of the hub's own players, by id */
data class AudioHubSources(val values: Map<String, String> = emptyMap()) {
    val hasSpotify: Boolean get() = "spotify.name" in values
    val hasAirPlay: Boolean get() = "airplay.name" in values
    val hasLibrary: Boolean get() = "mpd.name" in values

    fun with(id: String, value: String) = copy(values = values + (id to value))

    /** The edited values as JSON, null when nothing differs */
    fun changes(saved: AudioHubSources): String? {
        val changed = values.filter { saved.values[it.key] != it.value }.toSortedMap()
        if (changed.isEmpty()) return null
        return JsonObject(changed.mapValues { JsonPrimitive(it.value) }).toString()
    }

    companion object {
        const val PATH = "/gryonixnexus/settings"

        /** Reads the agent's JSON object of strings */
        fun parse(json: String): AudioHubSources {
            val found = runCatching { Json.parseToJsonElement(json) as? JsonObject }.getOrNull() ?: return AudioHubSources()
            return AudioHubSources(found.mapNotNull { (id, value) -> (value as? JsonPrimitive)?.let { id to it.content } }.toMap())
        }
    }
}
