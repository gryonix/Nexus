package com.skaymer.gryonixnexus.profile

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

object XrayConfiguration {
    private val json = Json { prettyPrint = false }

    @Throws(ProxyLinkConfig.ParseException::class)
    fun json(
        forLink: String,
        access: LocalProxyAccess,
        dns: List<String> = listOf("1.1.1.1", "8.8.8.8"),
    ): String = json.encodeToString(JsonElement.serializer(), document(forLink, access, dns))

    /** The same configuration from an already parsed link */
    fun json(
        link: ProxyLinkConfig,
        access: LocalProxyAccess,
        dns: List<String> = listOf("1.1.1.1", "8.8.8.8"),
    ): String = json.encodeToString(JsonElement.serializer(), document(link, access, dns))

    @Throws(ProxyLinkConfig.ParseException::class)
    fun document(
        forLink: String,
        access: LocalProxyAccess,
        dns: List<String> = listOf("1.1.1.1", "8.8.8.8"),
    ): JsonObject = document(ProxyLinkConfig.parse(forLink), access, dns)

    /** Idle connections close sooner, keeping the tunnel's memory small */
    const val IDLE_SECONDS = 30
    const val BUFFER_KILOBYTES = 4

    fun document(
        link: ProxyLinkConfig,
        access: LocalProxyAccess,
        dns: List<String> = listOf("1.1.1.1", "8.8.8.8"),
    ): JsonObject {
        return buildJsonObject {
            putJsonObject("log") { put("loglevel", "warning") }
            putJsonArray("inbounds") { add(inbound(access)) }
            putJsonArray("outbounds") {
                add(outbound(link))
                add(DNS_OUTBOUND)
                add(BLOCK_OUTBOUND)
            }
            putJsonObject("dns") {
                putJsonArray("servers") { dns.forEach { add(it) } }
                put("queryStrategy", "UseIP")
                put("tag", DNS_QUERY_TAG)
            }
            putJsonObject("routing") {
                put("domainStrategy", "AsIs")
                putJsonArray("rules") {
                    add(DNS_RULE)
                    add(DNS_QUERY_RULE)
                    add(QUIC_RULE)
                    add(PRIVATE_RULE)
                }
            }
            putJsonObject("policy") {
                putJsonObject("levels") {
                    putJsonObject("0") {
                        put("connIdle", IDLE_SECONDS)
                        put("bufferSize", BUFFER_KILOBYTES)
                    }
                }
            }
        }
    }

    /** Xray's own resolver: one shared connection, answers cached */
    private val DNS_OUTBOUND: JsonObject = buildJsonObject {
        put("tag", "dns-out")
        put("protocol", "dns")
        putJsonObject("settings") {
            putJsonArray("rules") {
                add(
                    buildJsonObject {
                        put("action", "hijack")
                        put("qType", "1,28")
                    },
                )
                add(
                    buildJsonObject {
                        put("action", "return")
                        put("rCode", 0)
                    },
                )
            }
        }
    }

    private val BLOCK_OUTBOUND: JsonObject = buildJsonObject {
        put("tag", "block")
        put("protocol", "blackhole")
    }

    /** QUIC refused: apps fall back to TCP, far cheaper here */
    private val QUIC_RULE: JsonObject = buildJsonObject {
        put("type", "field")
        put("network", "udp")
        put("port", "443")
        put("outboundTag", "block")
    }

    /** Xray's resolver reaches its servers through the server */
    const val DNS_QUERY_TAG = "dns-query"
    private val DNS_QUERY_RULE: JsonObject = buildJsonObject {
        put("type", "field")
        putJsonArray("inboundTag") { add(DNS_QUERY_TAG) }
        put("outboundTag", "proxy")
    }

    val PRIVATE_RANGES = listOf(
        "0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16",
        "172.16.0.0/12", "192.168.0.0/16", "198.18.0.0/15", "224.0.0.0/3",
        "::1/128", "fc00::/7", "fe80::/10", "ff00::/8",
    )

    /** Refused here, since the server holds them a minute */
    private val PRIVATE_RULE: JsonObject = buildJsonObject {
        put("type", "field")
        putJsonArray("ip") { PRIVATE_RANGES.forEach { add(it) } }
        put("outboundTag", "block")
    }

    /** Every DNS question from the device goes to that resolver */
    private val DNS_RULE: JsonObject = buildJsonObject {
        put("type", "field")
        putJsonArray("inboundTag") { add("socks-in") }
        put("port", "53")
        put("outboundTag", "dns-out")
    }

    internal fun inbound(access: LocalProxyAccess): JsonObject = buildJsonObject {
        put("tag", "socks-in")
        put("listen", "127.0.0.1")
        put("port", access.port)
        put("protocol", "socks")
        putJsonObject("settings") {
            put("auth", "password")
            putJsonArray("accounts") {
                add(
                    buildJsonObject {
                        put("user", access.username)
                        put("pass", access.password)
                    },
                )
            }
            put("udp", true)
        }
        putJsonObject("sniffing") {
            put("enabled", true)
            putJsonArray("destOverride") { add("http"); add("tls"); add("quic") }
        }
    }

    /** The one outbound: the server this link points at */
    internal fun outbound(link: ProxyLinkConfig): JsonObject = buildJsonObject {
        when (val credential = link.credential) {
            is ProxyLinkConfig.Credential.Shadowsocks -> {
                put("tag", "proxy")
                put("protocol", "shadowsocks")
                putJsonObject("settings") {
                    putJsonArray("servers") {
                        add(
                            buildJsonObject {
                                put("address", link.host)
                                put("port", link.port)
                                put("method", credential.method)
                                put("password", credential.password)
                                put("uot", true)
                            },
                        )
                    }
                }
            }
            is ProxyLinkConfig.Credential.Vless -> {
                put("tag", "proxy")
                put("protocol", "vless")
                putJsonObject("settings") {
                    putJsonArray("vnext") {
                        add(
                            buildJsonObject {
                                put("address", link.host)
                                put("port", link.port)
                                putJsonArray("users") { add(user(credential)) }
                            },
                        )
                    }
                }
                put("streamSettings", streamSettings(credential))
            }
        }
    }

    /** The VLESS user */
    private fun user(vless: ProxyLinkConfig.Credential.Vless): JsonObject = buildJsonObject {
        put("id", vless.uuid)
        put("encryption", "none")
        if (vless.flow.isNotEmpty()) put("flow", vless.flow)
    }

    private fun streamSettings(vless: ProxyLinkConfig.Credential.Vless): JsonObject =
        buildJsonObject {
            put("network", vless.network)
            when (vless.network) {
                "ws" -> putJsonObject("wsSettings") {
                    put("path", vless.path.ifEmpty { "/" })
                    if (vless.host.isNotEmpty()) {
                        putJsonObject("headers") { put("Host", vless.host) }
                    }
                }
                "grpc" -> putJsonObject("grpcSettings") { put("serviceName", vless.serviceName) }
            }
            when (vless.security) {
                "reality" -> {
                    put("security", "reality")
                    putJsonObject("realitySettings") {
                        put("publicKey", vless.publicKey)
                        put("shortId", vless.shortID)
                        put("fingerprint", vless.fingerprint.ifEmpty { "chrome" })
                        if (vless.sni.isNotEmpty()) put("serverName", vless.sni)
                    }
                }
                "tls" -> {
                    put("security", "tls")
                    putJsonObject("tlsSettings") {
                        put("allowInsecure", false)
                        if (vless.sni.isNotEmpty()) put("serverName", vless.sni)
                        if (vless.fingerprint.isNotEmpty()) put("fingerprint", vless.fingerprint)
                    }
                }
            }
        }
}
