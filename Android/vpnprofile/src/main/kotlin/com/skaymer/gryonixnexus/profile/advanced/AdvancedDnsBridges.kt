package com.skaymer.gryonixnexus.profile.advanced

import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

/** One domain answered with an IP address or another domain. */
@Serializable
data class AdvancedHostRewrite(
    val domain: String,
    val target: String,
    val id: String = UUID.randomUUID().toString(),
)

/** DNS over TLS through a loopback bridge, and host rewrites. */
object AdvancedDnsBridges {
    private const val DOT_PORT = 853

    internal class Bridge(val inbound: JsonObject, val outbound: JsonObject, val rule: JsonObject)

    /** DoT upstreams, each needing one loopback port */
    fun dotUpstreams(profile: AdvancedProfile): List<AdvancedDnsUpstream> =
        profile.dns.filter { it.kind == DnsKind.DOT && endpoint(it.address) != null }

    /** Host and port of a DoT address like dns.example:853 */
    fun endpoint(text: String): Pair<String, Int>? {
        val trimmed = text.trim().removePrefix("tls://")
        if (trimmed.count { it == ':' } > 1 && !trimmed.startsWith("[")) return trimmed to DOT_PORT
        val parts = ProxyLinkParts.parse("tls://$trimmed") ?: return null
        if (parts.host.isEmpty()) return null
        return parts.host to (parts.port ?: DOT_PORT)
    }

    internal fun bridges(
        profile: AdvancedProfile,
        options: AdvancedXrayConfiguration.Options,
        proxyTag: String,
    ): List<Bridge> = dotUpstreams(profile).mapIndexedNotNull { index, upstream ->
        val port = options.dotPorts[upstream.id] ?: return@mapIndexedNotNull null
        val (host, remotePort) = endpoint(upstream.address) ?: return@mapIndexedNotNull null
        bridge(index, host, remotePort, port, options.resolved[host] ?: host, proxyTag.takeIf { upstream.viaProxy })
    }

    private fun bridge(index: Int, host: String, remotePort: Int, localPort: Int, address: String, proxyTag: String?): Bridge {
        val inboundTag = "dot-in-$index"
        val outboundTag = "dot-$index"
        val inbound = buildJsonObject {
            put("tag", inboundTag)
            put("listen", "127.0.0.1")
            put("port", localPort)
            put("protocol", "dokodemo-door")
            putJsonObject("settings") { put("address", address); put("port", remotePort); put("network", "tcp") }
        }
        val outbound = buildJsonObject {
            put("tag", outboundTag)
            put("protocol", "freedom")
            putJsonObject("streamSettings") {
                put("network", "tcp")
                put("security", "tls")
                putJsonObject("tlsSettings") { put("serverName", host) }
            }
            if (proxyTag != null) putJsonObject("proxySettings") { put("tag", proxyTag) }
        }
        val rule = buildJsonObject {
            put("type", "field")
            putJsonArray("inboundTag") { add(inboundTag) }
            put("outboundTag", outboundTag)
        }
        return Bridge(inbound, outbound, rule)
    }

    internal fun hosts(profile: AdvancedProfile): JsonObject? {
        if (!profile.rewritesEnabled) return null
        val map = profile.hosts.map { it.domain.trim() to it.target.trim() }
            .filter { (domain, target) -> domain.isNotEmpty() && target.isNotEmpty() }
        if (map.isEmpty()) return null
        return buildJsonObject { map.forEach { (domain, target) -> put(if (':' in domain) domain else "full:$domain", target) } }
    }
}
