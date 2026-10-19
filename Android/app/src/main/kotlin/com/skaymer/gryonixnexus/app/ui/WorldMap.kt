package com.skaymer.gryonixnexus.app.ui

import android.content.res.AssetManager
import kotlin.math.hypot
import kotlin.math.max
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Country outlines from the bundled world-map.json, in map units */
class WorldMap(val width: Float, val height: Float, val countries: Map<String, Country>) {
    class Country(
        /** Absolute x, y pairs per ring */
        val rings: List<FloatArray>,
        val minX: Float,
        val maxX: Float,
        val minY: Float,
        val maxY: Float,
        val centerX: Float,
        val centerY: Float,
        /** Distance from the center to the farthest outline corner */
        val reach: Float,
        /** Too small for a shape, so drawn as a dot */
        val isTiny: Boolean,
    )

    /** The country under a point, preferring real shapes */
    fun countryAt(x: Float, y: Float, tolerance: Float): String? {
        countries.entries.firstOrNull { (_, country) ->
            !country.isTiny && country.rings.any { contains(it, x, y) }
        }?.let { return it.key }
        return countries.entries
            .map { it.key to hypot(it.value.centerX - x, it.value.centerY - y) }
            .filter { it.second <= tolerance }
            .minByOrNull { it.second }
            ?.first
    }

    @Serializable
    private class File(val w: Int, val h: Int, val c: Map<String, Entry>)

    @Serializable
    private class Entry(val x: Int, val y: Int, val r: List<List<Int>>)

    companion object {
        private const val TINY_EXTENT = 8f

        @Volatile
        private var cached: WorldMap? = null

        fun load(assets: AssetManager): WorldMap = cached ?: decode(
            assets.open("world-map.json").bufferedReader().use { it.readText() }
        ).also { cached = it }

        fun decode(json: String): WorldMap {
            val file = Json.decodeFromString<File>(json)
            return WorldMap(file.w.toFloat(), file.h.toFloat(), file.c.mapValues { country(it.value) })
        }

        private fun country(entry: Entry): Country {
            val rings = entry.r.map(::absolute)
            val xs = rings.flatMap { ring -> ring.filterIndexed { i, _ -> i % 2 == 0 } }
            val ys = rings.flatMap { ring -> ring.filterIndexed { i, _ -> i % 2 == 1 } }
            val cx = entry.x.toFloat()
            val cy = entry.y.toFloat()
            if (xs.isEmpty()) return Country(rings, cx, cx, cy, cy, cx, cy, 0f, isTiny = true)
            val reach = listOf(xs.min(), xs.max()).flatMap { x ->
                listOf(ys.min(), ys.max()).map { y -> hypot(x - cx, y - cy) }
            }.max()
            val extent = max(xs.max() - xs.min(), ys.max() - ys.min())
            return Country(rings, xs.min(), xs.max(), ys.min(), ys.max(), cx, cy, reach,
                           isTiny = extent < TINY_EXTENT)
        }

        private fun absolute(deltas: List<Int>): FloatArray {
            val out = FloatArray(deltas.size)
            var x = 0
            var y = 0
            for (i in 0 until deltas.size - 1 step 2) {
                x += deltas[i]
                y += deltas[i + 1]
                out[i] = x.toFloat()
                out[i + 1] = y.toFloat()
            }
            return out
        }

        /** Even-odd ray casting */
        private fun contains(ring: FloatArray, x: Float, y: Float): Boolean {
            var inside = false
            val count = ring.size / 2
            var j = count - 1
            for (i in 0 until count) {
                val xi = ring[2 * i]
                val yi = ring[2 * i + 1]
                val xj = ring[2 * j]
                val yj = ring[2 * j + 1]
                if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside
                j = i
            }
            return inside
        }
    }
}

/** One country turning on or off */
data class MapTransition(val isOn: Boolean, val startMillis: Long) {
    fun progress(nowMillis: Long): Float =
        ((nowMillis - startMillis).toFloat() / DURATION_MILLIS).coerceIn(0f, 1f)

    fun isFinished(nowMillis: Long) = progress(nowMillis) >= 1f

    companion object {
        const val DURATION_MILLIS = 700L
        const val MAX_STAGGER_MILLIS = 600L

        /** Delays that ripple outward from the group's middle */
        fun staggered(codes: Set<String>, map: WorldMap): Map<String, Long> {
            val centers = codes.mapNotNull { code -> map.countries[code]?.let { code to it } }
            if (centers.size < 2) return emptyMap()
            val midX = centers.map { it.second.centerX }.average().toFloat()
            val midY = centers.map { it.second.centerY }.average().toFloat()
            val distances = centers.map { (code, c) -> code to hypot(c.centerX - midX, c.centerY - midY) }
            val farthest = max(distances.maxOf { it.second }, 1f)
            return distances.associate { (code, d) -> code to (d / farthest * MAX_STAGGER_MILLIS).toLong() }
        }
    }
}
