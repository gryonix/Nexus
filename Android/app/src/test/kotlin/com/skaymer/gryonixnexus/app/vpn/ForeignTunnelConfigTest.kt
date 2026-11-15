package com.skaymer.gryonixnexus.app.vpn

import com.skaymer.gryonixnexus.app.secrets.InMemorySecretStore
import com.skaymer.gryonixnexus.catalog.ServiceID
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

class ForeignTunnelConfigTest {
    private val wireGuard = """
        [Interface]
        PrivateKey = cHJpdmF0ZWtleXByaXZhdGVrZXlwcml2YXRla2V5MTI=
        Address = 10.8.0.5/32
        DNS = 1.1.1.1

        [Peer]
        PublicKey = cHVibGlja2V5cHVibGlja2V5cHVibGlja2V5MTIzNA==
        AllowedIPs = 0.0.0.0/0
        Endpoint = vpn.example.net:51820
    """.trimIndent()

    @Test
    fun aWireGuardFileIsRecognised() {
        val detected = ForeignTunnelConfig.detect("\n$wireGuard\n")
        assertEquals(ServiceID.WIREGUARD_VPN, detected.protocol)
        assertEquals("vpn.example.net", detected.suggestedName)
        assertTrue(detected.text.startsWith("[Interface]"))
    }

    @Test
    fun obfuscationKeysMakeItAmneziaWG() {
        val amnezia = wireGuard.replace("DNS = 1.1.1.1", "DNS = 1.1.1.1\nJc = 4\nJmin = 10\nJmax = 50")
        assertEquals(ServiceID.AMNEZIA_WG, ForeignTunnelConfig.detect(amnezia).protocol)
    }

    @Test
    fun aShadowsocksLinkKeepsItsName() {
        val detected = ForeignTunnelConfig.detect("ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpzZWNyZXQ@203.0.113.9:8388#Home%20VPN")
        assertEquals(ServiceID.SHADOWSOCKS, detected.protocol)
        assertEquals("Home VPN", detected.suggestedName)
    }

    @Test
    fun aVLESSLinkIsRecognised() {
        val link = "vless://00000000-0000-4000-8000-000000000001@vpn.example.net:443?security=reality&sni=example.org&fp=chrome&pbk=cHVibGlj&sid=ab&type=tcp&flow=xtls-rprx-vision"
        val detected = ForeignTunnelConfig.detect(link)
        assertEquals(ServiceID.XRAY_REALITY, detected.protocol)
        assertEquals("vpn.example.net", detected.suggestedName)
    }

    @Test
    fun aCompressedAmneziaKeyBecomesItsWireGuardText() {
        val detected = ForeignTunnelConfig.detect("vpn://AAACoXicfVJtT8IwEP4rS-NHHHSDqEv4gIqARlzAIMKMqduhNV23dFUUwn_3rkDki6Zb9rxcb892XbO00FZIDaZikTdf_3KkTOQaVlIci-UrqyHFR-StmRKVfcbChSTO1gnbkgRZwuYDbcEsRApPSaI7WWagqry2xxv-qc_9oB4GqF8Ox6gdxaPBbWf0-Iy05h2Nuxd3w8sdx6LYyE9h4Qa-sTbtX5dZftWYPVgF0_NvMZ29Zb2JmU3VMs1V8DgdKRFMWrf3gzbuvU5xT5NALrV7vcPiC3GL8JgjChwKEIWE-qRxAiRRzn5IHoHmrh9e8xjA0NfFHy9Kpvt8E_nSU--U4S-M2VbDTpvydZQqlpANYvo3Dd-teqPmRVGdknR1VhZSW5cxRJPz0D-JWvzURY5xYLKyoO0NQCmU_ASqbFE-HFXC3orKDkUO25kctNjaZWEsWa7fhoZLCk3TKWyzeUItg4X4UPbinzORQZUaWVpZaHILQ4B0XXESzny3dlJAEm-eYZRgf5O1T0v2QVa2-QFUSckf")
        assertEquals(ServiceID.AMNEZIA_WG, detected.protocol)
        assertEquals("orion", detected.suggestedName)
        assertTrue("DNS = 9.9.9.9, 149.112.112.112" in detected.text)
        assertTrue("Endpoint = 203.0.113.7:51820" in detected.text)
    }

    @Test
    fun anUncompressedAmneziaKeyIsReadToo() {
        assertEquals("orion", ForeignTunnelConfig.detect("vpn://eyJjb250YWluZXJzIjogW3siY29udGFpbmVyIjogImFtbmV6aWEtYXdnIiwgImF3ZyI6IHsibGFzdF9jb25maWciOiAie1wiY29uZmlnXCI6IFwiW0ludGVyZmFjZV1cXG5BZGRyZXNzID0gMTAuOC4xLjIvMzJcXG5ETlMgPSAkUFJJTUFSWV9ETlMsICRTRUNPTkRBUllfRE5TXFxuUHJpdmF0ZUtleSA9IGNISnBkbUYwWld0bGVYQnlhWFpoZEdWclpYbHdjbWwyWVhSbGEyVjVNVEk9XFxuSmMgPSA0XFxuSm1pbiA9IDEwXFxuSm1heCA9IDUwXFxuUzEgPSAyMFxcblMyID0gMzBcXG5IMSA9IDFcXG5IMiA9IDJcXG5IMyA9IDNcXG5INCA9IDRcXG5cXG5bUGVlcl1cXG5QdWJsaWNLZXkgPSBjSFZpYkdsamEyVjVjSFZpYkdsamEyVjVjSFZpYkdsamEyVjVNVEl6TkE9PVxcbkFsbG93ZWRJUHMgPSAwLjAuMC4wLzAsIDo6LzBcXG5FbmRwb2ludCA9IDIwMy4wLjExMy43OjUxODIwXFxuUGVyc2lzdGVudEtlZXBhbGl2ZSA9IDI1XFxuXCIsIFwiaG9zdE5hbWVcIjogXCIyMDMuMC4xMTMuN1wiLCBcInBvcnRcIjogNTE4MjB9IiwgInBvcnQiOiAiNTE4MjAifX1dLCAiZGVmYXVsdENvbnRhaW5lciI6ICJhbW5lemlhLWF3ZyIsICJkZXNjcmlwdGlvbiI6ICJvcmlvbiIsICJkbnMxIjogIjkuOS45LjkiLCAiZG5zMiI6ICIxNDkuMTEyLjExMi4xMTIiLCAiaG9zdE5hbWUiOiAiMjAzLjAuMTEzLjcifQ").suggestedName)
    }

    @Test
    fun openVPNIsReadButNotCarried() {
        val failure = assertThrows<ForeignTunnelConfig.Failure> {
            ForeignTunnelConfig.detect("client\ndev tun\nremote vpn.example.net 1194\n")
        }
        assertEquals(ForeignTunnelConfig.Failure.NotCarried(ServiceID.OPEN_VPN), failure)
    }

    @Test
    fun noiseIsNotRecognised() {
        assertEquals(ForeignTunnelConfig.Failure.NotRecognised, assertThrows<ForeignTunnelConfig.Failure> { ForeignTunnelConfig.detect("hello") })
        assertEquals(ForeignTunnelConfig.Failure.Empty, assertThrows<ForeignTunnelConfig.Failure> { ForeignTunnelConfig.detect("  ") })
    }

    @Test
    fun aBrokenWireGuardFileIsUnreadable() {
        val failure = assertThrows<ForeignTunnelConfig.Failure> { ForeignTunnelConfig.detect("[Interface]\nAddress = 10.0.0.2/32\n") }
        assertEquals(ForeignTunnelConfig.Failure.Unreadable, failure)
    }

    @Test
    fun importedTunnelsAreKeptAndRemoved() {
        val store = ImportedTunnels(InMemorySecretStore())
        val entry = store.add(ForeignTunnelConfig.detect(wireGuard), "  ")
        assertEquals("vpn.example.net", entry.name)
        assertTrue(ImportedTunnels.isImported(entry.serverId))
        assertEquals(listOf(entry), store.all())
        store.remove(entry.id)
        assertEquals(emptyList(), store.all())
    }
}
