package com.skaymer.gryonixnexus.profile.advanced

import java.net.URLDecoder
import java.util.Base64

/** A proxy link cut into its parts without URL validation. */
internal class ProxyLinkParts private constructor(
    val scheme: String,
    val userInfo: String,
    val host: String,
    val port: Int?,
    val query: Map<String, String>,
    val fragment: String,
    /** Everything between the scheme and the query, for base64 forms */
    val body: String,
) {
    companion object {
        fun parse(text: String): ProxyLinkParts? {
            val schemeEnd = text.indexOf("://")
            if (schemeEnd < 0) return null
            val scheme = text.substring(0, schemeEnd).lowercase()
            var rest = text.substring(schemeEnd + 3)
            var fragment = ""
            rest.indexOf('#').takeIf { it >= 0 }?.let {
                fragment = percentDecoded(rest.substring(it + 1))
                rest = rest.substring(0, it)
            }
            var queryText = ""
            rest.indexOf('?').takeIf { it >= 0 }?.let {
                queryText = rest.substring(it + 1)
                rest = rest.substring(0, it)
            }
            val body = rest.removeSuffix("/")
            val at = body.lastIndexOf('@')
            val userInfo = if (at >= 0) body.substring(0, at) else ""
            val (host, port) = split(if (at >= 0) body.substring(at + 1) else body)
            return ProxyLinkParts(scheme, userInfo, host, port, parseQuery(queryText), fragment, body)
        }

        fun percentDecoded(text: String): String =
            runCatching { URLDecoder.decode(text.replace("+", "%2B"), "UTF-8") }.getOrDefault(text)

        private fun split(authority: String): Pair<String, Int?> {
            if (authority.startsWith("[")) {
                val close = authority.indexOf(']')
                if (close > 0) {
                    val tail = authority.substring(close + 1)
                    return authority.substring(1, close) to (if (tail.startsWith(":")) tail.drop(1).toIntOrNull() else null)
                }
            }
            val colon = authority.lastIndexOf(':')
            if (colon < 0) return authority to null
            return authority.substring(0, colon) to authority.substring(colon + 1).toIntOrNull()
        }

        private fun parseQuery(text: String): Map<String, String> {
            val result = LinkedHashMap<String, String>()
            for (pair in text.split('&')) {
                val index = pair.indexOf('=')
                if (index < 0) continue
                val value = percentDecoded(pair.substring(index + 1))
                if (value.isNotEmpty()) result[pair.substring(0, index)] = value
            }
            return result
        }
    }
}

internal object LinkBase64 {
    fun decode(text: String): String? {
        var normal = text.trim().replace('-', '+').replace('_', '/')
        if (normal.length % 4 > 0) normal += "=".repeat(4 - normal.length % 4)
        return runCatching { String(Base64.getDecoder().decode(normal), Charsets.UTF_8) }.getOrNull()
    }
}
