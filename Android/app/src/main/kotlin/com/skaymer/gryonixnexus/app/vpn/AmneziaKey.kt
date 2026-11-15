package com.skaymer.gryonixnexus.app.vpn

import java.util.Base64
import java.util.zip.Inflater
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** An Amnezia `vpn://` key holding a WireGuard or AmneziaWG tunnel */
object AmneziaKey {
    data class Decoded(val config: String, val name: String?)

    private const val SCHEME = "vpn://"
    private const val MAX_SIZE = 4_000_000

    /** The key inside the text, if any */
    fun link(text: String): String? {
        val start = text.indexOf(SCHEME)
        if (start < 0) return null
        return text.substring(start + SCHEME.length).takeWhile { !it.isWhitespace() }.ifEmpty { null }
    }

    fun decode(body: String): Decoded {
        val data = runCatching { Base64.getUrlDecoder().decode(body.trimEnd('=')) }.getOrNull()
            ?: throw ForeignTunnelConfig.Failure.Unreadable
        val json = inflated(data) ?: data
        val root = runCatching { Json.parseToJsonElement(json.decodeToString()).jsonObject }.getOrNull()
            ?: throw ForeignTunnelConfig.Failure.Unreadable
        val config = tunnelConfig(root) ?: throw ForeignTunnelConfig.Failure.Unreadable
        return Decoded(filled(config, root), root.text("description"))
    }

    /** Undoes Qt's qCompress: a length, then a zlib stream */
    fun inflated(data: ByteArray): ByteArray? {
        if (data.size <= 6 || data[4] != 0x78.toByte()) return null
        val size = data.take(4).fold(0) { sum, byte -> (sum shl 8) or (byte.toInt() and 0xFF) }
        if (size <= 0 || size > MAX_SIZE) return null
        val inflater = Inflater()
        return try {
            inflater.setInput(data, 4, data.size - 4)
            val output = ByteArray(size)
            if (inflater.inflate(output) == size) output else null
        } catch (_: Exception) {
            null
        } finally {
            inflater.end()
        }
    }

    /** The `wg-quick` text of the first WireGuard-like container */
    private fun tunnelConfig(root: JsonObject): String? {
        val containers = runCatching { root["containers"]?.jsonArray }.getOrNull() ?: return null
        for (container in containers) {
            for (key in listOf("awg", "wireguard")) {
                val last = runCatching { container.jsonObject[key]?.jsonObject?.text("last_config") }.getOrNull() ?: continue
                val inner = runCatching { Json.parseToJsonElement(last).jsonObject }.getOrNull() ?: continue
                inner.text("config")?.let { return it }
            }
        }
        return null
    }

    /** Fills the DNS placeholders Amnezia leaves in the text */
    private fun filled(config: String, root: JsonObject): String =
        config.replace("\$PRIMARY_DNS", root.text("dns1") ?: "1.1.1.1")
            .replace("\$SECONDARY_DNS", root.text("dns2") ?: "1.0.0.1")

    private fun JsonObject.text(key: String): String? =
        runCatching { this[key]?.jsonPrimitive?.content }.getOrNull()
}
