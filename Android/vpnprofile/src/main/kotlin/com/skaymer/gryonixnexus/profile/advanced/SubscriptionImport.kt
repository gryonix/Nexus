package com.skaymer.gryonixnexus.profile.advanced

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject

/** Reads a subscription body or one link into servers. */
object SubscriptionImport {
    internal val carriedNetworks = setOf("tcp", "ws", "grpc", "httpupgrade", "xhttp", "splithttp")
    private val carriedSecurities = setOf("none", "tls", "reality")

    sealed interface Outcome {
        data class Server(val server: AdvancedServer) : Outcome
        data class Skip(val skipped: AdvancedImportReport.Skipped) : Outcome
    }

    /** A subscription: base64 list, plain list, or Clash YAML */
    fun parse(body: String): AdvancedImportReport {
        val text = body.trim()
        if (ClashImport.looksLikeClash(text)) return ClashImport.parse(text)
        if ("://" !in text) {
            LinkBase64.decode(text)?.let { decoded ->
                return if (ClashImport.looksLikeClash(decoded)) ClashImport.parse(decoded) else parseLines(decoded)
            }
        }
        return parseLines(text)
    }

    private fun parseLines(text: String): AdvancedImportReport {
        val servers = mutableListOf<AdvancedServer>()
        val skipped = mutableListOf<AdvancedImportReport.Skipped>()
        for (raw in text.lines()) {
            val line = raw.trim()
            if ("://" !in line) continue
            when (val outcome = parseLink(line)) {
                is Outcome.Server -> servers.add(outcome.server)
                is Outcome.Skip -> skipped.add(outcome.skipped)
            }
        }
        return AdvancedImportReport(servers = servers, unsupported = skipped)
    }

    fun parseLink(link: String): Outcome = when (val scheme = link.substringBefore(':').lowercase()) {
        "vless" -> vless(link)
        "vmess" -> vmess(link)
        "trojan" -> trojan(link)
        "ss" -> shadowsocks(link)
        "hysteria2", "hy2" -> ExtraLinks.hysteria2(link)
        "naive+https" -> ExtraLinks.naive(link)
        else -> skip(link.take(40), "$scheme is not supported by the VPN engine")
    }

    internal fun skip(name: String, reason: String) = Outcome.Skip(AdvancedImportReport.Skipped(name, reason))

    internal fun skip(parts: ProxyLinkParts?, link: String, reason: String) =
        skip(parts?.fragment?.takeIf { it.isNotEmpty() } ?: link.take(40), reason)

    private fun vless(link: String): Outcome {
        val parts = ProxyLinkParts.parse(link)
        val port = parts?.port
        if (parts == null || port == null || parts.host.isEmpty() || parts.userInfo.isEmpty()) {
            return skip(null, link, "the link is incomplete")
        }
        val security = parts.query["security"] ?: "none"
        val network = parts.query["type"] ?: "tcp"
        if (security !in carriedSecurities) return skip(parts, link, "security $security")
        if (network !in carriedNetworks) return skip(parts, link, "transport $network")
        val fields = transportFields(parts.query, security, network).toMutableMap()
        fields["uuid"] = parts.userInfo
        if (security != "none") parts.query["flow"]?.let { fields["flow"] = it }
        return Outcome.Server(AdvancedServer.create(ServerKind.VLESS, parts.fragment, parts.host, port, fields))
    }

    private fun trojan(link: String): Outcome {
        val parts = ProxyLinkParts.parse(link)
        val port = parts?.port
        if (parts == null || port == null || parts.host.isEmpty() || parts.userInfo.isEmpty()) {
            return skip(null, link, "the link is incomplete")
        }
        val security = parts.query["security"] ?: "tls"
        val network = parts.query["type"] ?: "tcp"
        if (security !in carriedSecurities) return skip(parts, link, "security $security")
        if (network !in carriedNetworks) return skip(parts, link, "transport $network")
        val fields = transportFields(parts.query, security, network).toMutableMap()
        fields["password"] = ProxyLinkParts.percentDecoded(parts.userInfo)
        return Outcome.Server(AdvancedServer.create(ServerKind.TROJAN, parts.fragment, parts.host, port, fields))
    }

    internal fun transportFields(query: Map<String, String>, security: String, network: String): Map<String, String> {
        val fields = linkedMapOf("security" to security, "network" to network)
        val names = listOf(
            "alpn" to "alpn", "fp" to "fp", "host" to "host", "path" to "path", "pbk" to "pbk",
            "peer" to "sni", "serviceName" to "serviceName", "sid" to "sid", "sni" to "sni",
        )
        for ((key, name) in names) {
            val value = query[key]
            if (value != null && name !in fields) fields[name] = value
        }
        if (query["allowInsecure"] == "1" || query["insecure"] == "1") fields["insecure"] = "1"
        return fields
    }

    private fun vmess(link: String): Outcome {
        val decoded = LinkBase64.decode(link.removePrefix("vmess://"))
        val obj = decoded?.let { runCatching { Json.parseToJsonElement(it).jsonObject }.getOrNull() }
        val host = obj?.text("add")
        val uuid = obj?.text("id")
        val port = obj?.text("port")?.toIntOrNull()
        if (obj == null || host == null || uuid == null || port == null) return skip(null, link, "the link is incomplete")
        val name = obj.text("ps").orEmpty()
        val network = obj.text("net")?.ifEmpty { null } ?: "tcp"
        if (network !in carriedNetworks) return skip(name.ifEmpty { link.take(40) }, "transport $network")
        val fields = linkedMapOf(
            "uuid" to uuid, "network" to network, "security" to if (obj.text("tls") == "tls") "tls" else "none",
            "scy" to (obj.text("scy") ?: "auto"), "alterId" to (obj.text("aid")?.toIntOrNull() ?: 0).toString(),
        )
        for (key in listOf("sni", "host", "path", "fp", "alpn")) {
            obj.text(key)?.takeIf { it.isNotEmpty() }?.let { fields[key] = it }
        }
        if (network == "grpc") fields["path"]?.let { fields["serviceName"] = it }
        return Outcome.Server(AdvancedServer.create(ServerKind.VMESS, name, host, port, fields))
    }

    private fun JsonObject.text(key: String): String? = (this[key] as? JsonPrimitive)?.contentOrNull

    private class SsParts(val method: String, val password: String, val host: String, val port: Int)

    private fun shadowsocks(link: String): Outcome {
        val parts = ProxyLinkParts.parse(link) ?: return skip(null, link, "the link is incomplete")
        val found = ssParts(parts) ?: return skip(parts, link, "the link is incomplete")
        if (parts.query.containsKey("plugin")) return skip(parts, link, "plugins are not supported")
        val fields = mapOf("method" to found.method, "password" to found.password)
        return Outcome.Server(AdvancedServer.create(ServerKind.SHADOWSOCKS, parts.fragment, found.host, found.port, fields))
    }

    private fun ssParts(parts: ProxyLinkParts): SsParts? {
        val port = parts.port
        if (port != null && parts.userInfo.isNotEmpty() && parts.host.isNotEmpty()) {
            val plain = ProxyLinkParts.percentDecoded(parts.userInfo)
            val pair = if (':' in plain) plain else LinkBase64.decode(parts.userInfo).orEmpty()
            val colon = pair.indexOf(':')
            if (colon < 0) return null
            return SsParts(pair.substring(0, colon), pair.substring(colon + 1), parts.host, port)
        }
        val decoded = LinkBase64.decode(parts.body) ?: return null
        val at = decoded.lastIndexOf('@')
        if (at < 0) return null
        val inner = ProxyLinkParts.parse("ss://" + decoded.substring(at + 1)) ?: return null
        val innerPort = inner.port ?: return null
        val pair = decoded.substring(0, at)
        val colon = pair.indexOf(':')
        if (colon < 0) return null
        return SsParts(pair.substring(0, colon), pair.substring(colon + 1), inner.host, innerPort)
    }
}
