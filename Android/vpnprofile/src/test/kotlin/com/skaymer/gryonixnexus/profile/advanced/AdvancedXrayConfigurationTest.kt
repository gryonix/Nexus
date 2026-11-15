package com.skaymer.gryonixnexus.profile.advanced

import com.skaymer.gryonixnexus.profile.LocalProxyAccess
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class AdvancedXrayConfigurationTest {
    private val access = LocalProxyAccess(40123, "u", "p")

    private fun server(name: String, host: String) = AdvancedServer.create(
        ServerKind.TROJAN, name, host, 443,
        mapOf("password" to "pw", "network" to "tcp", "security" to "tls", "sni" to host),
    )

    private fun profile(): AdvancedProfile {
        val servers = listOf(server("A", "a.example.net"), server("B", "b.example.net"))
        return AdvancedProfile(servers = servers, activeID = servers[0].id)
    }

    private fun build(profile: AdvancedProfile, options: AdvancedXrayConfiguration.Options = AdvancedXrayConfiguration.Options()) =
        AdvancedXrayConfiguration.document(profile, access, options)

    private fun rules(document: JsonObject): List<JsonObject> =
        document["routing"]!!.jsonObject["rules"]!!.jsonArray.map { it.jsonObject }

    private fun strings(array: JsonArray?) = array?.map { it.jsonPrimitive.content }

    @Test
    fun rulesKeepOrderAndMergeNeighbours() {
        val profile = profile().copy(
            rules = listOf(
                AdvancedRule(RuleKind.DOMAIN_SUFFIX, "example.org", RuleAction.DIRECT),
                AdvancedRule(RuleKind.DOMAIN, "www.example.com", RuleAction.DIRECT),
                AdvancedRule(RuleKind.KEYWORD, "ads", RuleAction.BLOCK),
                AdvancedRule(RuleKind.IP, "203.0.113.0/24", RuleAction.PROXY),
            ),
            finalAction = RuleAction.DIRECT,
        )
        val document = build(profile)
        val list = rules(document)
        val user = list.filter { it["domain"] != null || strings(it["ip"]?.jsonArray) == listOf("203.0.113.0/24") }
        assertEquals(listOf("domain:example.org", "full:www.example.com"), strings(user[0]["domain"]?.jsonArray))
        assertEquals("direct", user[0]["outboundTag"]?.jsonPrimitive?.content)
        assertEquals(listOf("keyword:ads"), strings(user[1]["domain"]?.jsonArray))
        assertEquals("block", user[1]["outboundTag"]?.jsonPrimitive?.content)
        assertEquals("proxy", user[2]["outboundTag"]?.jsonPrimitive?.content)
        assertEquals("direct", list.last()["outboundTag"]?.jsonPrimitive?.content)
        assertEquals("IPIfNonMatch", document["routing"]!!.jsonObject["domainStrategy"]?.jsonPrimitive?.content)
    }

    @Test
    fun geoipUsesDownloadedNetworks() {
        var profile = profile().copy(
            rules = listOf(
                AdvancedRule(RuleKind.GEOIP, "cn", RuleAction.DIRECT),
                AdvancedRule(RuleKind.IP, "203.0.113.0/24", RuleAction.DIRECT),
            ),
        )
        assertEquals(1, AdvancedXrayConfiguration.skippedRules(profile).size)
        assertEquals(1, rules(build(profile)).count { it["outboundTag"]?.jsonPrimitive?.content == "direct" })
        profile = profile.copy(geoip = AdvancedGeoIP(ranges = mapOf("CN" to listOf("1.0.1.0/24", "1.0.2.0/23"))))
        assertTrue(AdvancedXrayConfiguration.skippedRules(profile).isEmpty())
        val merged = rules(build(profile)).first { strings(it["ip"]?.jsonArray)?.firstOrNull() == "1.0.1.0/24" }
        assertEquals(listOf("1.0.1.0/24", "1.0.2.0/23", "203.0.113.0/24"), strings(merged["ip"]?.jsonArray))
        val withPrivate = profile.rules + AdvancedRule(RuleKind.GEOIP, "private", RuleAction.DIRECT)
        assertEquals(setOf("CN"), AdvancedGeoIP.codes(withPrivate))
    }

    @Test
    fun hysteria2NaiveAndShadowsocks2022Outbounds() {
        val hy = AdvancedServer.create(ServerKind.HYSTERIA2, "H", "h.example.net", 443,
            mapOf("password" to "pw", "obfs" to "salamander", "obfsPassword" to "o"))
        val naive = AdvancedServer.create(ServerKind.NAIVE, "N", "n.example.net", 443, mapOf("user" to "me", "password" to "pw"))
        val ss = AdvancedServer.create(ServerKind.SHADOWSOCKS, "S", "s.example.net", 8388,
            mapOf("method" to "2022-blake3-aes-128-gcm", "password" to "k"))
        val group = AdvancedGroup("Auto", GroupMode.AUTO, listOf(hy.id, naive.id, ss.id))
        val profile = AdvancedProfile(servers = listOf(hy, naive, ss), groups = listOf(group), activeID = group.id)
        assertEquals(listOf(ss.id), AdvancedProtocols.ss2022Members(profile).map { it.id })
        val document = build(profile, AdvancedXrayConfiguration.Options(ss2022Ports = mapOf(ss.id to 41000)))
        val outbounds = document["outbounds"]!!.jsonArray.map { it.jsonObject }
        assertEquals("hysteria", outbounds[0]["protocol"]?.jsonPrimitive?.content)
        val stream = outbounds[0]["streamSettings"]!!.jsonObject
        assertEquals("hysteria", stream["network"]?.jsonPrimitive?.content)
        assertEquals("pw", stream["hysteriaSettings"]!!.jsonObject["auth"]?.jsonPrimitive?.content)
        assertNotNull(stream["finalmask"])
        assertEquals("http", outbounds[1]["protocol"]?.jsonPrimitive?.content)
        assertEquals("me", outbounds[1]["settings"]!!.jsonObject["user"]?.jsonPrimitive?.content)
        assertEquals("socks", outbounds[2]["protocol"]?.jsonPrimitive?.content)
        assertTrue(outbounds[2].toString().contains("41000"))
    }

    @Test
    fun dotRunsThroughALoopbackBridge() {
        val dot = AdvancedDnsUpstream(DnsKind.DOT, "dns.example.net", listOf("example.org"))
        val skipped = AdvancedDnsUpstream(DnsKind.DOT, "other.example.net")
        val options = AdvancedXrayConfiguration.Options(
            resolved = mapOf("dns.example.net" to "198.51.100.1"),
            dotPorts = mapOf(dot.id to 41001),
        )
        val document = build(profile().copy(dns = listOf(dot, skipped)), options)
        val servers = document["dns"]!!.jsonObject["servers"]!!.jsonArray
        assertEquals("tcp+local://127.0.0.1:41001", servers[0].jsonObject["address"]?.jsonPrimitive?.content)
        assertEquals(1 + options.dns.size, servers.size)
        val inbound = document["inbounds"]!!.jsonArray.last().jsonObject
        assertEquals(41001, inbound["port"]?.jsonPrimitive?.content?.toInt())
        assertEquals("198.51.100.1", inbound["settings"]!!.jsonObject["address"]?.jsonPrimitive?.content)
        assertEquals("853", inbound["settings"]!!.jsonObject["port"]?.jsonPrimitive?.content)
        val bridge = document["outbounds"]!!.jsonArray.last().jsonObject
        assertEquals("freedom", bridge["protocol"]?.jsonPrimitive?.content)
        assertEquals("proxy", bridge["proxySettings"]!!.jsonObject["tag"]?.jsonPrimitive?.content)
        assertEquals("dot-0", rules(document).first()["outboundTag"]?.jsonPrimitive?.content)
        assertEquals(8853, AdvancedDnsBridges.endpoint("[2001:db8::1]:8853")?.second)
        assertEquals("2001:db8::1", AdvancedDnsBridges.endpoint("2001:db8::1")?.first)
    }

    @Test
    fun hostRewritesOnlyWhenEnabled() {
        val profile = profile().copy(hosts = listOf(AdvancedHostRewrite("a.example.org", "203.0.113.9")))
        assertNull(build(profile)["dns"]!!.jsonObject["hosts"])
        val hosts = build(profile.copy(rewritesEnabled = true))["dns"]!!.jsonObject["hosts"]!!.jsonObject
        assertEquals("203.0.113.9", hosts["full:a.example.org"]?.jsonPrimitive?.content)
    }

    @Test
    fun autoGroupBuildsLeastPingBalancer() {
        val base = profile()
        val group = AdvancedGroup("Auto", GroupMode.AUTO, base.servers.map { it.id })
        val document = build(base.copy(groups = listOf(group), activeID = group.id))
        val balancer = document["routing"]!!.jsonObject["balancers"]!!.jsonArray[0].jsonObject
        assertEquals(listOf("s0", "s1"), strings(balancer["selector"]?.jsonArray))
        assertEquals("leastPing", balancer["strategy"]!!.jsonObject["type"]?.jsonPrimitive?.content)
        assertEquals(listOf("s0", "s1"), strings(document["observatory"]!!.jsonObject["subjectSelector"]?.jsonArray))
        assertEquals("auto", rules(document).last()["balancerTag"]?.jsonPrimitive?.content)
        val tags = document["outbounds"]!!.jsonArray.map { it.jsonObject["tag"]!!.jsonPrimitive.content }
        assertEquals(listOf("s0", "s1"), tags.take(2))
    }

    @Test
    fun manualGroupUsesTheChosenServerOnly() {
        val base = profile()
        val group = AdvancedGroup("Pick", GroupMode.MANUAL, base.servers.map { it.id }, base.servers[1].id)
        val document = build(base.copy(groups = listOf(group), activeID = group.id))
        assertNull(document["observatory"])
        val first = document["outbounds"]!!.jsonArray[0].jsonObject
        assertEquals("proxy", first["tag"]?.jsonPrimitive?.content)
        assertTrue(first.toString().contains("b.example.net"))
    }

    @Test
    fun dnsUpstreams() {
        val profile = profile().copy(
            dns = listOf(
                AdvancedDnsUpstream(DnsKind.DOH, "dns.example.net", listOf("example.org"), false),
                AdvancedDnsUpstream(DnsKind.DOH, "https://doh.example.net/dns-query"),
                AdvancedDnsUpstream(DnsKind.DOQ, "q.example.net"),
            ),
        )
        val servers = build(profile)["dns"]!!.jsonObject["servers"]!!.jsonArray
        val scoped = servers[0].jsonObject
        assertEquals("https+local://dns.example.net/dns-query", scoped["address"]?.jsonPrimitive?.content)
        assertEquals(listOf("domain:example.org"), strings(scoped["domains"]?.jsonArray))
        assertEquals("https://doh.example.net/dns-query", servers[1].jsonPrimitive.content)
        assertEquals("quic+local://q.example.net", servers[2].jsonPrimitive.content)
        assertEquals("8.8.8.8", servers.last().jsonPrimitive.content)
    }

    @Test
    fun blockListBecomesBlockRule() {
        val profile = profile().copy(blockLists = listOf(AdvancedBlockList("https://example.net/l.txt", listOf("ads.example.net"))))
        val block = rules(build(profile)).firstOrNull { strings(it["domain"]?.jsonArray) == listOf("domain:ads.example.net") }
        assertEquals("block", block?.get("outboundTag")?.jsonPrimitive?.content)
    }

    @Test
    fun resolvedAddressKeepsServerName() {
        val options = AdvancedXrayConfiguration.Options(resolved = mapOf("a.example.net" to "203.0.113.5"))
        val text = build(profile(), options)["outbounds"]!!.jsonArray[0].toString()
        assertTrue(text.contains("203.0.113.5"))
        assertTrue(text.contains("a.example.net"))
    }

    @Test
    fun statsAddsApi() {
        val document = build(profile(), AdvancedXrayConfiguration.Options(statsPort = 10085))
        assertNotNull(document["stats"])
        assertEquals("127.0.0.1:10085", document["metrics"]!!.jsonObject["listen"]?.jsonPrimitive?.content)
    }

    @Test
    fun noActiveTargetThrows() {
        assertThrows<AdvancedXrayConfiguration.NoActiveServerException> { build(AdvancedProfile()) }
    }
}

class AdvancedTrafficTest {
    @Test
    fun statsSplitDirectAndProxy() {
        val json = """{"stats":{"outbound":{"proxy":{"uplink":100,"downlink":900},"direct":{"uplink":5,"downlink":20},"block":{"uplink":1}},"inbound":{"socks-in":{"uplink":7}}}}"""
        val traffic = AdvancedTraffic.fromMetrics(json)
        assertEquals(AdvancedTraffic.Counter(100, 900), traffic.proxy)
        assertEquals(AdvancedTraffic.Counter(5, 20), traffic.direct)
    }

    @Test
    fun accessLogLines() {
        val log = "2026/11/07 10:00:01 from tcp:127.0.0.1:5000 accepted tcp:www.example.com:443 [socks-in -> direct]\n" +
            "2026/11/07 10:00:02 from tcp:127.0.0.1:5001 accepted udp:ads.example.net:443 [socks-in -> block]\nnoise"
        val requests = AdvancedTraffic.requests(log)
        assertEquals(listOf("www.example.com", "ads.example.net"), requests.map { it.domain })
        assertEquals(listOf("direct", "block"), requests.map { it.route })
    }

    @Test
    fun advancedLineSurvivesTunnelText() {
        val text = com.skaymer.gryonixnexus.profile.ProxyTunnelText.compose("advanced", listOf("9.9.9.9"), "{\"a\":1}")
        val split = com.skaymer.gryonixnexus.profile.ProxyTunnelText.split(text)
        assertEquals("advanced", split.first)
        assertEquals(listOf("9.9.9.9"), split.second)
        assertEquals("{\"a\":1}", com.skaymer.gryonixnexus.profile.ProxyTunnelText.advancedJson(text))
    }
}
