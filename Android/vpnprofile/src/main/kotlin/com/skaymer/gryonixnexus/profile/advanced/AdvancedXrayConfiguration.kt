package com.skaymer.gryonixnexus.profile.advanced

import com.skaymer.gryonixnexus.profile.LocalProxyAccess
import com.skaymer.gryonixnexus.profile.ProxyTunnelText
import com.skaymer.gryonixnexus.profile.Tun2SocksConfiguration
import com.skaymer.gryonixnexus.profile.XrayConfiguration
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

/** Builds the xray JSON for an advanced profile. */
object AdvancedXrayConfiguration {
    const val BALANCER_TAG = "auto"
    const val PROBE_URL = "https://www.gstatic.com/generate_204"
    const val MEMBER_LIMIT = 40
    const val STATS_API_PORT = 10085

    private val json = Json { prettyPrint = false }

    class NoActiveServerException : Exception("no active server")

    data class Options(
        val dns: List<String> = ProxyTunnelText.fallbackDNS,
        /** Host to IP, resolved before the tunnel is up */
        val resolved: Map<String, String> = emptyMap(),
        val statsPort: Int? = null,
        val accessLogPath: String? = null,
        /** Server id to its local Shadowsocks client port */
        val ss2022Ports: Map<String, Int> = emptyMap(),
        /** DNS upstream id to its local DoT bridge port */
        val dotPorts: Map<String, Int> = emptyMap(),
    )

    /** The servers the active target runs, in order */
    fun members(profile: AdvancedProfile): List<AdvancedServer> {
        profile.activeGroup?.let { group ->
            val all = group.memberIDs.mapNotNull { profile.server(it) }
            if (all.isEmpty()) throw NoActiveServerException()
            if (group.mode == GroupMode.AUTO) return all.take(MEMBER_LIMIT)
            return all.filter { it.id == group.chosenID }.take(1)
        }
        return listOf(profile.activeServer ?: throw NoActiveServerException())
    }

    fun usesBalancer(profile: AdvancedProfile): Boolean = profile.activeGroup?.mode == GroupMode.AUTO

    fun json(profile: AdvancedProfile, access: LocalProxyAccess, options: Options = Options()): String =
        json.encodeToString(JsonElement.serializer(), document(profile, access, options))

    fun document(profile: AdvancedProfile, access: LocalProxyAccess, options: Options = Options()): JsonObject {
        val servers = members(profile)
        if (servers.isEmpty()) throw NoActiveServerException()
        val balanced = usesBalancer(profile)
        val tags = servers.indices.map { if (balanced) "s$it" else "proxy" }
        val bridges = AdvancedDnsBridges.bridges(profile, options, tags.first())
        return buildJsonObject {
            putJsonObject("log") {
                put("loglevel", "warning")
                options.accessLogPath?.let { put("access", it) }
            }
            putJsonArray("inbounds") {
                add(XrayConfiguration.inbound(access))
                bridges.forEach { add(it.inbound) }
            }
            putJsonArray("outbounds") {
                servers.zip(tags).forEach { (server, tag) -> add(outbound(server, tag, options, access)) }
                add(XrayConfiguration.DNS_OUTBOUND)
                add(XrayConfiguration.BLOCK_OUTBOUND)
                add(buildJsonObject { put("tag", "direct"); put("protocol", "freedom") })
                bridges.forEach { add(it.outbound) }
            }
            put("dns", dnsSection(profile, options))
            putJsonObject("routing") {
                put("domainStrategy", if (needsIpMatching(profile)) "IPIfNonMatch" else "AsIs")
                put("rules", JsonArray(bridges.map { it.rule } + rules(profile, balanced)))
                if (balanced) putJsonArray("balancers") { add(balancer(tags)) }
            }
            putJsonObject("policy") {
                putJsonObject("levels") {
                    putJsonObject("0") {
                        put("connIdle", XrayConfiguration.IDLE_SECONDS)
                        put("bufferSize", XrayConfiguration.BUFFER_KILOBYTES)
                    }
                }
                if (options.statsPort != null) {
                    putJsonObject("system") {
                        put("statsOutboundUplink", true)
                        put("statsOutboundDownlink", true)
                    }
                }
            }
            if (balanced) put("observatory", observatory(tags))
            if (options.statsPort != null) {
                putJsonObject("stats") {}
                putJsonObject("metrics") { put("listen", "127.0.0.1:${options.statsPort}") }
            }
        }
    }

    // MARK: Outbounds

    internal fun outbound(server: AdvancedServer, tag: String, options: Options, access: LocalProxyAccess): JsonObject {
        val address = options.resolved[server.host] ?: server.host
        if (AdvancedProtocols.isShadowsocks2022(server)) {
            return AdvancedProtocols.localSocks(tag, options.ss2022Ports[server.id] ?: 0, access)
        }
        when (server.kind) {
            ServerKind.HYSTERIA2 -> return AdvancedProtocols.hysteria2(server, tag, address)
            ServerKind.NAIVE -> return AdvancedProtocols.naive(server, tag, address)
            else -> Unit
        }
        val fields = server.fields
        return buildJsonObject {
            put("tag", tag)
            put("protocol", server.kind.name.lowercase())
            putJsonObject("settings") {
                when (server.kind) {
                    ServerKind.VLESS -> putJsonArray("vnext") {
                        add(vnext(address, server.port, buildJsonObject {
                            put("id", fields["uuid"].orEmpty())
                            put("encryption", "none")
                            fields["flow"]?.let { put("flow", it) }
                        }))
                    }
                    ServerKind.VMESS -> putJsonArray("vnext") {
                        add(vnext(address, server.port, buildJsonObject {
                            put("id", fields["uuid"].orEmpty())
                            put("security", fields["scy"] ?: "auto")
                            put("alterId", fields["alterId"]?.toIntOrNull() ?: 0)
                        }))
                    }
                    ServerKind.TROJAN -> putJsonArray("servers") {
                        add(buildJsonObject {
                            put("address", address)
                            put("port", server.port)
                            put("password", fields["password"].orEmpty())
                        })
                    }
                    ServerKind.SHADOWSOCKS -> putJsonArray("servers") {
                        add(buildJsonObject {
                            put("address", address)
                            put("port", server.port)
                            put("method", fields["method"].orEmpty())
                            put("password", fields["password"].orEmpty())
                            put("uot", true)
                        })
                    }
                    ServerKind.WIREGUARD -> wireguardSettings(server, address)
                    ServerKind.HYSTERIA2, ServerKind.NAIVE -> Unit
                }
            }
            if (server.kind != ServerKind.WIREGUARD && server.kind != ServerKind.SHADOWSOCKS) {
                put("streamSettings", streamSettings(server, address))
            }
        }
    }

    private fun vnext(address: String, port: Int, user: JsonObject) = buildJsonObject {
        put("address", address)
        put("port", port)
        putJsonArray("users") { add(user) }
    }

    private fun kotlinx.serialization.json.JsonObjectBuilder.wireguardSettings(server: AdvancedServer, address: String) {
        val fields = server.fields
        put("secretKey", fields["secretKey"].orEmpty())
        putJsonArray("address") { fields["address"].orEmpty().split(',').filter { it.isNotEmpty() }.forEach { add(it) } }
        putJsonArray("peers") {
            add(buildJsonObject {
                put("publicKey", fields["publicKey"].orEmpty())
                put("endpoint", "${if (':' in address) "[$address]" else address}:${server.port}")
                putJsonArray("allowedIPs") { add("0.0.0.0/0"); add("::/0") }
                fields["preSharedKey"]?.let { put("preSharedKey", it) }
            })
        }
        put("mtu", fields["mtu"]?.toIntOrNull() ?: Tun2SocksConfiguration.MTU)
        fields["reserved"]?.let { text ->
            putJsonArray("reserved") { text.split(',').mapNotNull { it.toIntOrNull() }.forEach { add(it) } }
        }
    }

    internal fun streamSettings(server: AdvancedServer, address: String): JsonObject {
        val fields = server.fields
        val network = fields["network"] ?: "tcp"
        val xrayNetwork = if (network == "xhttp") "splithttp" else network
        val path = fields["path"]?.takeIf { it.isNotEmpty() } ?: "/"
        val name = fields["sni"] ?: if (address == server.host) "" else server.host
        return buildJsonObject {
            put("network", xrayNetwork)
            when (xrayNetwork) {
                "ws" -> putJsonObject("wsSettings") {
                    put("path", path)
                    fields["host"]?.let { host -> putJsonObject("headers") { put("Host", host) } }
                }
                "grpc" -> putJsonObject("grpcSettings") { put("serviceName", fields["serviceName"].orEmpty()) }
                "httpupgrade", "splithttp" -> putJsonObject(if (xrayNetwork == "httpupgrade") "httpupgradeSettings" else "splithttpSettings") {
                    put("path", path)
                    fields["host"]?.let { put("host", it) }
                }
            }
            when (fields["security"] ?: "none") {
                "reality" -> {
                    put("security", "reality")
                    putJsonObject("realitySettings") {
                        put("publicKey", fields["pbk"].orEmpty())
                        put("shortId", fields["sid"].orEmpty())
                        put("fingerprint", fields["fp"] ?: "chrome")
                        if (name.isNotEmpty()) put("serverName", name)
                    }
                }
                "tls" -> {
                    put("security", "tls")
                    putJsonObject("tlsSettings") {
                        put("allowInsecure", fields["insecure"] == "1")
                        if (name.isNotEmpty()) put("serverName", name)
                        fields["fp"]?.let { put("fingerprint", it) }
                        fields["alpn"]?.let { alpn -> putJsonArray("alpn") { alpn.split(',').forEach { add(it) } } }
                    }
                }
            }
        }
    }

    // MARK: Balancer

    internal fun balancer(tags: List<String>): JsonObject = buildJsonObject {
        put("tag", BALANCER_TAG)
        put("selector", JsonArray(tags.map { JsonPrimitive(it) }))
        putJsonObject("strategy") { put("type", "leastPing") }
        put("fallbackTag", tags.firstOrNull() ?: "direct")
    }

    internal fun observatory(tags: List<String>): JsonObject = buildJsonObject {
        put("subjectSelector", JsonArray(tags.map { JsonPrimitive(it) }))
        put("probeURL", PROBE_URL)
        put("probeInterval", "5m")
        put("enableConcurrency", true)
    }

    // MARK: Rules

    private fun needsIpMatching(profile: AdvancedProfile) =
        profile.rules.any { it.kind == RuleKind.IP || it.kind == RuleKind.GEOIP }

    /** Country rules without downloaded networks, for the screen */
    fun skippedRules(profile: AdvancedProfile): List<AdvancedRule> =
        profile.rules.filter { it.kind == RuleKind.GEOIP && profile.geoip.networks(it.value) == null }

    private fun target(action: RuleAction, balanced: Boolean): Pair<String, String> = when (action) {
        RuleAction.DIRECT -> "outboundTag" to "direct"
        RuleAction.BLOCK -> "outboundTag" to "block"
        RuleAction.PROXY -> if (balanced) "balancerTag" to BALANCER_TAG else "outboundTag" to "proxy"
    }

    private fun rules(profile: AdvancedProfile, balanced: Boolean): List<JsonObject> {
        val result = mutableListOf<JsonObject>(XrayConfiguration.DNS_RULE)
        val (queryKey, queryValue) = target(RuleAction.PROXY, balanced)
        result.add(buildJsonObject {
            put("type", "field")
            putJsonArray("inboundTag") { add(XrayConfiguration.DNS_QUERY_TAG) }
            put(queryKey, queryValue)
        })
        result.add(XrayConfiguration.QUIC_RULE)
        result += blockListRules(profile.blockLists)
        result += userRules(profile.rules, balanced, profile.geoip)
        result.add(XrayConfiguration.PRIVATE_RULE)
        val (finalKey, finalValue) = target(profile.finalAction, balanced)
        result.add(buildJsonObject {
            put("type", "field")
            put("network", "tcp,udp")
            put(finalKey, finalValue)
        })
        return result
    }

    private fun blockListRules(lists: List<AdvancedBlockList>): List<JsonObject> {
        val domains = lists.flatMap { it.domains }.map { "domain:$it" }
        if (domains.isEmpty()) return emptyList()
        return listOf(buildJsonObject {
            put("type", "field")
            put("domain", JsonArray(domains.map { JsonPrimitive(it) }))
            put("outboundTag", "block")
        })
    }

    private class Group(val field: String, val action: RuleAction, val values: MutableList<String>)

    internal fun userRules(rules: List<AdvancedRule>, balanced: Boolean, geoip: AdvancedGeoIP): List<JsonObject> {
        val grouped = mutableListOf<Group>()
        for (rule in rules) {
            val (field, values) = match(rule, geoip) ?: continue
            val last = grouped.lastOrNull()
            if (last != null && last.field == field && last.action == rule.action) {
                last.values.addAll(values)
            } else {
                grouped.add(Group(field, rule.action, values.toMutableList()))
            }
        }
        return grouped.map { group ->
            val (key, value) = target(group.action, balanced)
            buildJsonObject {
                put("type", "field")
                put(key, value)
                put(group.field, JsonArray(group.values.map { JsonPrimitive(it) }))
            }
        }
    }

    private fun match(rule: AdvancedRule, geoip: AdvancedGeoIP): Pair<String, List<String>>? {
        val value = rule.value.trim()
        if (value.isEmpty()) return null
        return when (rule.kind) {
            RuleKind.DOMAIN -> "domain" to listOf("full:$value")
            RuleKind.DOMAIN_SUFFIX -> "domain" to listOf("domain:$value")
            RuleKind.KEYWORD -> "domain" to listOf("keyword:$value")
            RuleKind.IP -> "ip" to listOf(value)
            RuleKind.GEOIP -> geoip.networks(value)?.let { "ip" to it }
        }
    }

    // MARK: DNS

    internal fun dnsSection(profile: AdvancedProfile, options: Options): JsonObject {
        val upstreams = profile.dns.filter { it.kind != DnsKind.DOT || options.dotPorts.containsKey(it.id) }
        val scoped = upstreams.filter { it.domains.isNotEmpty() }
        val global = upstreams.filter { it.domains.isEmpty() }
        return buildJsonObject {
            put("servers", buildJsonArray {
                scoped.forEach { add(dnsServer(it, true, options)) }
                global.forEach { add(dnsServer(it, false, options)) }
                options.dns.forEach { add(it) }
            })
            put("queryStrategy", "UseIP")
            put("tag", XrayConfiguration.DNS_QUERY_TAG)
            AdvancedDnsBridges.hosts(profile)?.let { put("hosts", it) }
        }
    }

    internal fun dnsAddress(upstream: AdvancedDnsUpstream, options: Options = Options()): String {
        val text = upstream.address.trim()
        return when (upstream.kind) {
            DnsKind.PLAIN -> text
            DnsKind.DOT -> "tcp+local://127.0.0.1:${options.dotPorts[upstream.id] ?: 0}"
            DnsKind.TCP -> "tcp${if (upstream.viaProxy) "" else "+local"}://$text"
            DnsKind.DOQ -> "quic+local://$text"
            DnsKind.DOH -> {
                val full = if (text.startsWith("https://")) text else "https://$text/dns-query"
                if (upstream.viaProxy) full else full.replaceFirst("https://", "https+local://")
            }
        }
    }

    private fun dnsServer(upstream: AdvancedDnsUpstream, scoped: Boolean, options: Options): JsonElement {
        val address = dnsAddress(upstream, options)
        if (!scoped) return JsonPrimitive(address)
        return buildJsonObject {
            put("address", address)
            put("domains", JsonArray(upstream.domains.map { JsonPrimitive(if (':' in it) it else "domain:$it") }))
            put("skipFallback", true)
        }
    }
}
