package com.skaymer.gryonixnexus.profile.advanced

import com.skaymer.gryonixnexus.profile.LocalProxyAccess
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

/** Hysteria2, NaiveProxy and blake3 Shadowsocks outbounds. */
object AdvancedProtocols {
    fun isShadowsocks2022(server: AdvancedServer): Boolean =
        server.kind == ServerKind.SHADOWSOCKS && server.fields["method"].orEmpty().startsWith("2022-")

    /** Members that need a local blake3 Shadowsocks client */
    fun ss2022Members(profile: AdvancedProfile): List<AdvancedServer> =
        runCatching { AdvancedXrayConfiguration.members(profile) }.getOrDefault(emptyList()).filter(::isShadowsocks2022)

    internal fun localSocks(tag: String, port: Int, access: LocalProxyAccess): JsonObject = buildJsonObject {
        put("tag", tag)
        put("protocol", "socks")
        putJsonObject("settings") {
            putJsonArray("servers") {
                add(buildJsonObject {
                    put("address", "127.0.0.1")
                    put("port", port)
                    putJsonArray("users") {
                        add(buildJsonObject { put("user", access.username); put("pass", access.password) })
                    }
                })
            }
        }
    }

    internal fun hysteria2(server: AdvancedServer, tag: String, address: String): JsonObject {
        val fields = server.fields
        return buildJsonObject {
            put("tag", tag)
            put("protocol", "hysteria")
            putJsonObject("settings") { put("version", 2); put("address", address); put("port", server.port) }
            putJsonObject("streamSettings") {
                put("network", "hysteria")
                put("security", "tls")
                putJsonObject("tlsSettings") {
                    put("allowInsecure", fields["insecure"] == "1")
                    putJsonArray("alpn") { add("h3") }
                    (fields["sni"] ?: server.host).takeIf { it.isNotEmpty() }?.let { put("serverName", it) }
                }
                putJsonObject("hysteriaSettings") { put("version", 2); put("auth", fields["password"].orEmpty()) }
                val secret = fields["obfsPassword"]
                if (fields["obfs"] == "salamander" && secret != null) {
                    putJsonObject("finalmask") {
                        putJsonArray("udp") {
                            add(buildJsonObject {
                                put("type", "salamander")
                                putJsonObject("settings") { put("password", secret) }
                            })
                        }
                    }
                }
            }
        }
    }

    /** HTTP/2 CONNECT over TLS, which NaiveProxy servers accept */
    internal fun naive(server: AdvancedServer, tag: String, address: String): JsonObject {
        val fields = server.fields
        return buildJsonObject {
            put("tag", tag)
            put("protocol", "http")
            putJsonObject("settings") {
                put("address", address)
                put("port", server.port)
                fields["user"]?.takeIf { it.isNotEmpty() }?.let { put("user", it); put("pass", fields["password"].orEmpty()) }
            }
            putJsonObject("streamSettings") {
                put("network", "tcp")
                put("security", "tls")
                putJsonObject("tlsSettings") {
                    put("serverName", fields["sni"] ?: server.host)
                    putJsonArray("alpn") { add("h2"); add("http/1.1") }
                    put("fingerprint", "chrome")
                    put("allowInsecure", fields["insecure"] == "1")
                }
            }
        }
    }
}
