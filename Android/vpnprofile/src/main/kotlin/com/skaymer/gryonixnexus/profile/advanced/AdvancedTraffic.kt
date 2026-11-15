package com.skaymer.gryonixnexus.profile.advanced

import java.text.SimpleDateFormat
import java.util.Locale
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

/** Per-session traffic split and the in-memory request log. */
data class AdvancedTraffic(
    val direct: Counter = Counter(),
    val proxy: Counter = Counter(),
    val requests: List<Request> = emptyList(),
) {
    data class Counter(val uploaded: Long = 0, val downloaded: Long = 0) {
        val total: Long get() = uploaded + downloaded
    }

    data class Request(val timeMillis: Long, val domain: String, val route: String)

    companion object {
        const val REQUEST_LIMIT = 200
        const val STATS_PORT = 10085

        /** Reads xray's metrics answer: outbound counters by tag */
        fun fromMetrics(json: String): AdvancedTraffic {
            val outbound = runCatching {
                Json.parseToJsonElement(json).jsonObject["stats"]?.jsonObject?.get("outbound")?.jsonObject
            }.getOrNull() ?: return AdvancedTraffic()
            var direct = Counter()
            var proxy = Counter()
            for ((tag, value) in outbound) {
                val counter = Counter(value.counter("uplink"), value.counter("downlink"))
                if (tag == "direct") {
                    direct = counter
                } else if (tag == "proxy" || tag.startsWith("s")) {
                    proxy = Counter(proxy.uploaded + counter.uploaded, proxy.downloaded + counter.downloaded)
                }
            }
            return AdvancedTraffic(direct, proxy)
        }

        private fun kotlinx.serialization.json.JsonElement.counter(key: String): Long =
            (this as? JsonObject)?.get(key)?.jsonPrimitive?.longOrNull ?: 0L

        /** Reads xray access-log lines into requests, newest last */
        fun requests(log: String): List<Request> = log.lines().mapNotNull { request(it) }.takeLast(REQUEST_LIMIT)

        internal fun request(line: String): Request? {
            val accepted = line.indexOf(" accepted ")
            val open = line.lastIndexOf('[')
            val close = line.lastIndexOf(']')
            if (accepted < 0 || open < 0 || close < open) return null
            val target = line.substring(accepted + " accepted ".length, open).trim()
            val hostPort = target.substringAfter(':')
            val domain = hostPort.substringBeforeLast(':', hostPort)
            if (domain.isEmpty()) return null
            val route = line.substring(open + 1, close).substringAfterLast("->").trim()
            val time = runCatching { SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.US).parse(line.take(19))?.time }
                .getOrNull() ?: System.currentTimeMillis()
            return Request(time, domain, if (route.startsWith("s") && route != "socks-in") "proxy" else route)
        }
    }
}
