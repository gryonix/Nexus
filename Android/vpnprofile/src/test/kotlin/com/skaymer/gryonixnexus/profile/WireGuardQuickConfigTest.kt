package com.skaymer.gryonixnexus.profile

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows

class WireGuardQuickConfigTest {
    private val valid = """
        [Interface]
        PrivateKey = mInDaw06K0NgfULRObHJjkWD3ahUC8XC1tVjIf6W+Vo=
        Address = 10.9.0.4/32
        DNS = 10.9.0.1

        [Peer]
        PublicKey = JRI8Xc0zKP9kXk8qP84NdUQA04h6DLfFbwJn4g+/PFs=
        Endpoint = vpn.example.com:51820
        AllowedIPs = 0.0.0.0/0
    """.trimIndent()

    private fun assertRefuses(text: String, expected: WireGuardQuickConfig.ParseFailure) {
        val thrown = assertThrows<WireGuardQuickConfig.ParseException> {
            WireGuardQuickConfig.parse(text)
        }
        assertEquals(expected, thrown.failure)
    }

    @Test
    fun `repeated address and allowed ips lines are all read`() {
        val text = valid
            .replace("Address = 10.9.0.4/32", "Address = 10.9.0.4/32\nAddress = fd09::4/128")
            .replace("AllowedIPs = 0.0.0.0/0", "AllowedIPs = 0.0.0.0/0\nAllowedIPs = ::/0")
        val config = WireGuardQuickConfig.parse(text)
        assertEquals(listOf("10.9.0.4/32", "fd09::4/128"), config.addresses)
        assertEquals(listOf("0.0.0.0/0", "::/0"), config.allowedIPs)
    }

    @Test
    fun `a config with two peers is refused`() {
        val text = valid + "\n\n[Peer]\nPublicKey = JRI8Xc0zKP9kXk8qP84NdUQA04h6DLfFbwJn4g+/PFs=\nEndpoint = b.example.com:1\n"
        assertRefuses(text, WireGuardQuickConfig.ParseFailure.SEVERAL_PEERS)
    }

    @Test
    fun `parses the endpoint and the name`() {
        val config = WireGuardQuickConfig.parse(valid)
        assertEquals("vpn.example.com:51820", config.endpoint)
        assertEquals("vpn.example.com", config.name)
    }

    /** The text is what the tunnel actually reads */
    @Test
    fun `the text is kept verbatim apart from surrounding whitespace`() {
        assertEquals(valid, WireGuardQuickConfig.parse("\n\n$valid\n  ").rawText)
    }

    @Test
    fun `an IPv6 endpoint yields the address without brackets`() {
        val config = WireGuardQuickConfig.parse(
            valid.replace("vpn.example.com:51820", "[2001:db8::1]:51820"),
        )
        assertEquals("[2001:db8::1]:51820", config.endpoint)
        assertEquals("2001:db8::1", config.name)
    }

    @Test
    fun `section headers are matched case insensitively`() {
        val shouted = valid.replace("[Interface]", "[INTERFACE]").replace("[Peer]", "[peer]")
        assertEquals("vpn.example.com:51820", WireGuardQuickConfig.parse(shouted).endpoint)
    }

    @Test
    fun `keys are matched case insensitively`() {
        val config = WireGuardQuickConfig.parse(valid.replace("Endpoint =", "endpoint ="))
        assertEquals("vpn.example.com:51820", config.endpoint)
    }

    // ------------------------------------------------------------- Refusals

    @Test
    fun `text that is not a wireguard config is refused`() {
        assertRefuses(
            "ss://YWVzOnBhc3N3b3Jk@example.com:8388",
            WireGuardQuickConfig.ParseFailure.MISSING_INTERFACE,
        )
        assertRefuses(
            "[Interface]\nPrivateKey = x",
            WireGuardQuickConfig.ParseFailure.MISSING_PEER,
        )
        assertRefuses(
            "[Interface]\nPrivateKey = x\n[Peer]\nPublicKey = y",
            WireGuardQuickConfig.ParseFailure.MISSING_ENDPOINT,
        )
    }

    @Test
    fun `an empty endpoint is refused however it is spelled`() {
        assertRefuses(
            "[Interface]\nPrivateKey = x\n[Peer]\nEndpoint =   ",
            WireGuardQuickConfig.ParseFailure.MISSING_ENDPOINT,
        )
        assertRefuses(
            "[Interface]\nPrivateKey = x\n[Peer]\nEndpoint =",
            WireGuardQuickConfig.ParseFailure.MISSING_ENDPOINT,
        )
    }

    // ---------------------------------------- What the comments promised

    @Test
    fun `blank lines and whole-line comments are ordinary content`() {
        val padded = """
            [Interface]

            # the client's own key
            PrivateKey = mInDaw06K0NgfULRObHJjkWD3ahUC8XC1tVjIf6W+Vo=

            Address = 10.9.0.4/32

            [Peer]
            # where the server is
            Endpoint = vpn.example.com:51820
        """.trimIndent()
        val config = WireGuardQuickConfig.parse(padded)
        assertEquals("vpn.example.com:51820", config.endpoint)
        assertEquals(listOf("10.9.0.4/32"), config.addresses)
    }

    /** A trailing comment is not part of the value */
    @Test
    fun `a trailing comment is cut off the value`() {
        val config = WireGuardQuickConfig.parse(
            valid.replace("Endpoint = vpn.example.com:51820",
                          "Endpoint = vpn.example.com:51820  # the relay"),
        )
        assertEquals("vpn.example.com:51820", config.endpoint)
    }

    @Test
    fun `a value containing equals signs survives whole`() {
        val config = WireGuardQuickConfig.parse(valid)
        assertEquals("JRI8Xc0zKP9kXk8qP84NdUQA04h6DLfFbwJn4g+/PFs=", config.peerPublicKey)
    }

    /** The same key means different things in the two sections */
    @Test
    fun `a key is read from its own section`() {
        val both = """
            [Interface]
            PublicKey = INTERFACE-KEY
            Address = 10.9.0.4/32

            [Peer]
            PublicKey = PEER-KEY
            Endpoint = vpn.example.com:51820
        """.trimIndent()
        assertEquals("PEER-KEY", WireGuardQuickConfig.parse(both).peerPublicKey)
    }

    // --------------------------------------------------------- Obfuscation

    @Test
    fun `obfuscation values are read in the panels order`() {
        val amnezia = """
            [Interface]
            PrivateKey = mInDaw06K0NgfULRObHJjkWD3ahUC8XC1tVjIf6W+Vo=
            Address = 10.10.0.4/32
            H4 = 1357924680
            H1 = 1106457487
            Jc = 4
            Jmin = 40
            Jmax = 70
            S1 = 78
            S2 = 61
            H2 = 1234567890
            H3 = 987654321

            [Peer]
            Endpoint = vpn.example.com:51821
        """.trimIndent()
        val config = WireGuardQuickConfig.parse(amnezia)
        assertTrue(config.isObfuscated)
        assertEquals(
            listOf("Jc", "Jmin", "Jmax", "S1", "S2", "H1", "H2", "H3", "H4"),
            config.obfuscation.map { it.first },
            "the order is the contract's, not the file's",
        )
        assertEquals("1106457487", config.obfuscation.single { it.first == "H1" }.second)
    }

    @Test
    fun `a plain configuration is not obfuscated`() {
        val config = WireGuardQuickConfig.parse(valid)
        assertTrue(config.obfuscation.isEmpty())
        assertEquals(false, config.isObfuscated)
    }

    // ------------------------------------------------------- Optional fields

    /** Absent optional fields are absent, not zero */
    @Test
    fun `absent optional fields stay absent`() {
        val config = WireGuardQuickConfig.parse(valid)
        assertNull(config.mtu)
        assertNull(config.persistentKeepalive)
        assertTrue(config.dns.isNotEmpty())
    }

    /** Comma-separated lists are split and trimmed; empties are dropped */
    @Test
    fun `comma separated lists are split and trimmed`() {
        val config = WireGuardQuickConfig.parse(
            valid.replace("AllowedIPs = 0.0.0.0/0", "AllowedIPs = 0.0.0.0/0, ::/0 ,"),
        )
        assertEquals(listOf("0.0.0.0/0", "::/0"), config.allowedIPs)
    }

    @Test
    fun `two configurations with the same text are equal`() {
        assertEquals(WireGuardQuickConfig.parse(valid), WireGuardQuickConfig.parse("\n$valid\n"))
    }
}
