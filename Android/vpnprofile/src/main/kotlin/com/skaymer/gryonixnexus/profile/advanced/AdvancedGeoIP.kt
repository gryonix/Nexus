package com.skaymer.gryonixnexus.profile.advanced

import com.skaymer.gryonixnexus.profile.XrayConfiguration
import kotlinx.serialization.Serializable

/** Country networks cut from a downloaded geoip.dat file. */
@Serializable
data class AdvancedGeoIP(
    val url: String = DEFAULT_URL,
    /** Country code, upper case, to its CIDR networks */
    val ranges: Map<String, List<String>> = emptyMap(),
    val updatedAtMillis: Long? = null,
) {
    /** Networks for one rule value, null when unknown */
    fun networks(value: String): List<String>? {
        val code = value.trim().uppercase()
        if (code == PRIVATE_CODE) return XrayConfiguration.PRIVATE_RANGES
        return ranges[code]?.takeIf { it.isNotEmpty() }
    }

    companion object {
        const val DEFAULT_URL = "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat"
        private const val PRIVATE_CODE = "PRIVATE"

        /** Country codes the rules ask for */
        fun codes(rules: List<AdvancedRule>): Set<String> =
            rules.filter { it.kind == RuleKind.GEOIP }.map { it.value.trim().uppercase() }
                .filter { it.isNotEmpty() && it != PRIVATE_CODE }.toSet()
    }
}

/** Reads the v2ray GeoIPList protobuf without a protobuf library. */
object GeoIPDatParser {
    class MalformedException : Exception("malformed geoip.dat")

    /** Networks for the wanted codes; others are skipped unread */
    fun ranges(data: ByteArray, codes: Set<String>): Map<String, List<String>> {
        val reader = ProtoReader(data, 0, data.size)
        val result = mutableMapOf<String, List<String>>()
        while (!reader.atEnd) {
            val (field, wire) = reader.key()
            if (field != 1 || wire != 2) { reader.skip(wire); continue }
            country(reader.lengthDelimited(), codes)?.let { (code, networks) -> result[code] = networks }
        }
        return result
    }

    private fun country(entry: ProtoReader, codes: Set<String>): Pair<String, List<String>>? {
        var code = ""
        val networks = mutableListOf<String>()
        while (!entry.atEnd) {
            val (field, wire) = entry.key()
            when {
                field == 1 && wire == 2 -> {
                    code = entry.lengthDelimited().text().uppercase()
                    if (code !in codes) return null
                }
                field == 2 && wire == 2 -> cidr(entry.lengthDelimited())?.let { networks.add(it) }
                else -> entry.skip(wire)
            }
        }
        return if (code.isEmpty()) null else code to networks
    }

    private fun cidr(entry: ProtoReader): String? {
        var address = ByteArray(0)
        var prefix = 0
        while (!entry.atEnd) {
            val (field, wire) = entry.key()
            when {
                field == 1 && wire == 2 -> address = entry.lengthDelimited().bytes()
                field == 2 && wire == 0 -> prefix = entry.varint().toInt()
                else -> entry.skip(wire)
            }
        }
        val octets = address.map { it.toInt() and 0xFF }
        if (octets.size == 4) return octets.joinToString(".") + "/$prefix"
        if (octets.size != 16) return null
        return (0 until 16 step 2).joinToString(":") { (octets[it] shl 8 or octets[it + 1]).toString(16) } + "/$prefix"
    }
}

internal class ProtoReader(private val data: ByteArray, private var index: Int, private val end: Int) {
    val atEnd: Boolean get() = index >= end

    fun varint(): Long {
        var value = 0L
        var shift = 0
        while (true) {
            if (index >= end || shift >= 64) throw GeoIPDatParser.MalformedException()
            val byte = data[index++].toInt() and 0xFF
            value = value or ((byte and 0x7F).toLong() shl shift)
            if (byte and 0x80 == 0) return value
            shift += 7
        }
    }

    fun key(): Pair<Int, Int> {
        val raw = varint()
        return (raw ushr 3).toInt() to (raw and 7).toInt()
    }

    fun lengthDelimited(): ProtoReader {
        val length = varint()
        if (length < 0 || index + length > end) throw GeoIPDatParser.MalformedException()
        val start = index
        index += length.toInt()
        return ProtoReader(data, start, index)
    }

    fun bytes(): ByteArray = data.copyOfRange(index, end)

    fun text(): String = String(data, index, end - index, Charsets.UTF_8)

    fun skip(wire: Int) {
        when (wire) {
            0 -> varint()
            1 -> index += 8
            2 -> lengthDelimited()
            5 -> index += 4
            else -> throw GeoIPDatParser.MalformedException()
        }
        if (index > end) throw GeoIPDatParser.MalformedException()
    }
}
