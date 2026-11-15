package com.skaymer.gryonixnexus.profile.advanced

import java.util.Base64
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue

class AdvancedImportTest {
    private val vless = "vless://3f1c0e2a-6a5b-4c7d-8e9f-0a1b2c3d4e5f@a.example.net:443" +
        "?security=reality&sni=www.example.org&fp=chrome&pbk=KEY&sid=9a&type=tcp&flow=xtls-rprx-vision#Berlin"
    private val trojan = "trojan://secret@b.example.net:443?sni=b.example.net&type=ws&path=%2Fws#Paris"
    private val ss = "ss://YWVzLTI1Ni1nY206cGFzcw@c.example.net:8388#Oslo"
    private val vmess: String
        get() {
            val json = """{"v":"2","ps":"Rome","add":"d.example.net","port":"443","id":"uuid-1","aid":"0","net":"ws","tls":"tls","path":"/p","host":"h.example.net"}"""
            return "vmess://" + Base64.getEncoder().encodeToString(json.toByteArray())
        }

    private fun server(link: String) = (SubscriptionImport.parseLink(link) as? SubscriptionImport.Outcome.Server)?.server

    @Test
    fun base64SubscriptionListsSupportedLinks() {
        val list = listOf(vless, vmess, trojan, ss, "tuic://x@h.example.net:443#Fast").joinToString("\n")
        val report = SubscriptionImport.parse(Base64.getEncoder().encodeToString(list.toByteArray()))
        assertEquals(
            listOf(ServerKind.VLESS, ServerKind.VMESS, ServerKind.TROJAN, ServerKind.SHADOWSOCKS),
            report.servers.map { it.kind },
        )
        assertEquals(listOf("Berlin", "Rome", "Paris", "Oslo"), report.servers.map { it.name })
        assertEquals(1, report.unsupported.size)
        assertTrue(report.unsupported[0].reason.contains("tuic"))
    }

    @Test
    fun linkFields() {
        assertEquals("KEY", server(vless)?.fields?.get("pbk"))
        assertEquals("xtls-rprx-vision", server(vless)?.fields?.get("flow"))
        assertEquals("ws", server(vmess)?.fields?.get("network"))
        assertEquals("h.example.net", server(vmess)?.fields?.get("host"))
        assertEquals("aes-256-gcm", server(ss)?.fields?.get("method"))
    }

    @Test
    fun shadowsocks2022IsKeptAndPluginsAreSkipped() {
        val key = Base64.getEncoder().encodeToString("2022-blake3-aes-256-gcm:key".toByteArray())
        assertTrue(AdvancedProtocols.isShadowsocks2022(server("ss://$key@e.example.net:1#X")!!))
        assertNull(server("ss://YWVzLTI1Ni1nY206cGFzcw@c.example.net:8388?plugin=obfs#Oslo"))
    }

    @Test
    fun clashProxiesAndRules() {
        val yaml = """
            proxies:
              - {name: "HK 1", type: ss, server: h.example.net, port: 8388, cipher: aes-128-gcm, password: pw}
              - name: DE
                type: vless
                server: de.example.net
                port: 443
                uuid: abc
                tls: true
                servername: de.example.net
                network: ws
                ws-opts:
                  path: /ws
                  headers:
                    Host: cdn.example.net
              - {name: Fast, type: hysteria2, server: f.example.net, port: 1}
            rules:
              - DOMAIN-SUFFIX,example.org,DIRECT
              - DOMAIN-KEYWORD,ads,REJECT # comment
              - IP-CIDR,10.1.0.0/16,Proxy,no-resolve
              - PROCESS-NAME,app,DIRECT
              - MATCH,Proxy
        """.trimIndent()
        val report = ClashImport.parse(yaml)
        assertEquals(listOf("HK 1", "DE"), report.servers.map { it.name })
        assertEquals("cdn.example.net", report.servers[1].fields["host"])
        assertEquals("/ws", report.servers[1].fields["path"])
        assertEquals(listOf(RuleAction.DIRECT, RuleAction.BLOCK, RuleAction.PROXY), report.rules.map { it.action })
        assertEquals(listOf(RuleKind.DOMAIN_SUFFIX, RuleKind.KEYWORD, RuleKind.IP), report.rules.map { it.kind })
        assertEquals(3, report.unsupported.size)
    }

    @Test
    fun hysteria2AndNaiveLinks() {
        val hy = server("hy2://secret@h.example.net:8443/?sni=s.example.net&obfs=salamander&obfs-password=o&insecure=1#Fast")!!
        assertEquals(ServerKind.HYSTERIA2, hy.kind)
        assertEquals(8443, hy.port)
        assertEquals("secret", hy.fields["password"])
        assertEquals("o", hy.fields["obfsPassword"])
        assertNull(server("hysteria2://s@h.example.net:443,2000-3000#R"))
        val naive = server("naive+https://me:pw@n.example.net#N")!!
        assertEquals(ServerKind.NAIVE, naive.kind)
        assertEquals(443, naive.port)
        assertEquals("me", naive.fields["user"])
        assertEquals("pw", naive.fields["password"])
    }

    @Test
    fun clashHysteria2AndShadowsocks2022() {
        val yaml = """
            proxies:
              - {name: H, type: hysteria2, server: h.example.net, port: 443, password: pw, obfs: salamander, obfs-password: o}
              - {name: S, type: ss, server: s.example.net, port: 1, cipher: 2022-blake3-aes-128-gcm, password: k}
              - {name: T, type: tuic, server: t.example.net, port: 1}
        """.trimIndent()
        val report = ClashImport.parse(yaml)
        assertEquals(listOf(ServerKind.HYSTERIA2, ServerKind.SHADOWSOCKS), report.servers.map { it.kind })
        assertEquals("salamander", report.servers[0].fields["obfs"])
        assertEquals(listOf("T"), report.unsupported.map { it.name })
    }

    @Test
    fun geoipDatKeepsWantedCountries() {
        val data = geoipDat(
            listOf(
                Triple("RU", byteArrayOf(10, 0, 0, 0), 8),
                Triple("CN", byteArrayOf(1, 2, 3, 0), 24),
                Triple("DE", byteArrayOf(0x20, 0x01, 0x0d, 0xb8.toByte()) + ByteArray(12), 32),
            ),
        )
        val ranges = GeoIPDatParser.ranges(data, setOf("CN", "DE"))
        assertEquals(listOf("1.2.3.0/24"), ranges["CN"])
        assertEquals(listOf("2001:db8:0:0:0:0:0:0/32"), ranges["DE"])
        assertNull(ranges["RU"])
        assertThrows<GeoIPDatParser.MalformedException> { GeoIPDatParser.ranges(byteArrayOf(0x0A, 0x50), setOf("CN")) }
    }

    private fun geoipDat(countries: List<Triple<String, ByteArray, Int>>): ByteArray {
        var list = ByteArray(0)
        for ((code, address, prefix) in countries) {
            val cidr = field(1, address) + byteArrayOf(0x10, prefix.toByte())
            list += field(1, field(1, code.toByteArray()) + field(2, cidr))
        }
        return list
    }

    private fun field(number: Int, bytes: ByteArray): ByteArray {
        val varint = mutableListOf<Byte>()
        var length = bytes.size
        do {
            varint.add(((length and 0x7F) or (if (length > 0x7F) 0x80 else 0)).toByte())
            length = length ushr 7
        } while (length > 0)
        return byteArrayOf((number shl 3 or 2).toByte()) + varint.toByteArray() + bytes
    }

    @Test
    fun subscriptionBodyThatIsClash() {
        val report = SubscriptionImport.parse(
            "proxies:\n  - {name: A, type: trojan, server: t.example.net, port: 443, password: p}\n",
        )
        assertEquals(ServerKind.TROJAN, report.servers.firstOrNull()?.kind)
    }

    @Test
    fun blockListFormats() {
        val text = "# list\n0.0.0.0 ads.example.net\n||track.example.org^\nplain.example.com\n127.0.0.1 localhost\n! note\n"
        assertEquals(listOf("ads.example.net", "track.example.org", "plain.example.com"), BlockListParser.domains(text))
    }
}
