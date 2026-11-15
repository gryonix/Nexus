package com.skaymer.gryonixnexus.servercontrol

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlin.math.roundToInt

/** The audio hub as odio-api reports it */
data class AudioHubState(
    val volume: Double = 0.0,
    val muted: Boolean = false,
    val outputs: List<Output> = emptyList(),
    val players: List<Player> = emptyList(),
    val services: List<Service> = emptyList(),
    val bluetoothPowered: Boolean = false,
    val bluetoothPairing: Boolean = false,
) {
    data class Output(val name: String, val title: String, val volume: Double, val muted: Boolean, val isDefault: Boolean)

    data class Player(
        val busName: String,
        val identity: String,
        val status: String,
        val title: String,
        val artist: String,
        val canGoNext: Boolean,
        val canGoPrevious: Boolean,
    ) {
        val isPlaying: Boolean get() = status == "Playing"
    }

    data class Service(val unit: String, val title: String, val running: Boolean)

    companion object {
        /** Players the hub can switch on and off */
        val SWITCHABLE_UNITS = listOf(
            "spotifyd.service", "shairport-sync.service", "mpd.service", "snapclient.service", "upmpdcli.service"
        )

        fun percent(volume: Double): Int = (volume * 100).roundToInt()
    }
}

/** Builds [AudioHubState] from odio-api JSON bodies */
object AudioHubParser {
    private val json = Json { ignoreUnknownKeys = true }

    fun withServer(body: String, state: AudioHubState): AudioHubState {
        val obj = objectOf(body) ?: return state
        return state.copy(volume = obj.number("volume"), muted = obj.flag("muted"))
    }

    fun outputs(body: String): List<AudioHubState.Output> = itemsOf(body).mapNotNull { item ->
        val name = item.text("name") ?: return@mapNotNull null
        AudioHubState.Output(
            name, item.text("description") ?: item.text("nick") ?: name,
            item.number("volume"), item.flag("muted"), item.flag("default"),
        )
    }

    fun players(body: String): List<AudioHubState.Player> = itemsOf(body).mapNotNull { item ->
        val bus = item.text("bus_name") ?: return@mapNotNull null
        val metadata = item["metadata"] as? JsonObject ?: JsonObject(emptyMap())
        val caps = item["capabilities"] as? JsonObject ?: JsonObject(emptyMap())
        AudioHubState.Player(
            bus, item.text("identity") ?: bus, item.text("playback_status").orEmpty(),
            metadata.text("xesam:title").orEmpty(), artist(metadata["xesam:artist"]),
            caps.flag("can_go_next"), caps.flag("can_go_previous"),
        )
    }

    fun services(body: String): List<AudioHubState.Service> = itemsOf(body).mapNotNull { item ->
        val unit = item.text("name") ?: return@mapNotNull null
        val exists = (item["exists"] as? JsonPrimitive)?.booleanOrNull ?: true
        if (item.text("scope") != "user" || unit !in AudioHubState.SWITCHABLE_UNITS || !exists) return@mapNotNull null
        AudioHubState.Service(unit, item.text("description") ?: unit, item.flag("running"))
    }

    fun withBluetooth(body: String, state: AudioHubState): AudioHubState {
        val obj = objectOf(body) ?: return state
        return state.copy(bluetoothPowered = obj.flag("powered"), bluetoothPairing = obj.flag("pairing_active"))
    }

    /** JSON body for a volume between 0 and 1 */
    fun volumeBody(volume: Double): String =
        "{\"volume\":${String.format(java.util.Locale.ROOT, "%.2f", volume.coerceIn(0.0, 1.0))}}"

    private fun artist(value: JsonElement?): String = when (value) {
        is JsonPrimitive -> value.content
        is JsonArray -> value.joinToString(", ") { it.jsonPrimitive.content }
        else -> ""
    }

    private fun parse(body: String): JsonElement? = runCatching { json.parseToJsonElement(body) }.getOrNull()

    private fun objectOf(body: String): JsonObject? = parse(body) as? JsonObject

    private fun itemsOf(body: String): List<JsonObject> =
        (parse(body) as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()

    private fun JsonObject.text(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

    private fun JsonObject.flag(key: String): Boolean = (this[key] as? JsonPrimitive)?.booleanOrNull ?: false

    private fun JsonObject.number(key: String): Double = (this[key] as? JsonPrimitive)?.doubleOrNull ?: 0.0
}
