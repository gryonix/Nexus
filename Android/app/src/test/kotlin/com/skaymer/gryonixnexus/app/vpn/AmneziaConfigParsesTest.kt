package com.skaymer.gryonixnexus.app.vpn

import java.io.ByteArrayInputStream
import java.io.File
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Test
import org.amnezia.awg.config.Config

/** The linked runtime reads what the panel writes */
class AmneziaConfigParsesTest {
    private fun golden(protocol: String): String {
        val resources = "Apple/Packages/gryonixNexus/Tests/VPNTunnelTests/Resources"
        val root = generateSequence(File("").absoluteFile) { it.parentFile }
            .first { File(it, resources).isDirectory }
        val file = File(root, "$resources/panel-vpn-configs.json")
        assertTrue(file.exists(), "no panel golden at ${file.path}")
        val cases = Json.parseToJsonElement(file.readText()).jsonObject["cases"]!!.jsonArray
        val entry = cases.map { it.jsonObject }
            .first { it["protocol"]!!.jsonPrimitive.content == protocol }
        return entry["text"]!!.jsonPrimitive.content
    }

    @Test
    fun `the captured AmneziaWG configuration parses and keeps its obfuscation`() {
        val config = Config.parse(ByteArrayInputStream(golden("amneziawg").toByteArray()))
        val iface = config.`interface`

        assertEquals(1280, iface.mtu.orElse(0))

        assertTrue(iface.junkPacketCount.isPresent, "the obfuscation values did not survive")
        assertTrue(iface.junkPacketMaxSize.isPresent)
        assertTrue(iface.responsePacketJunkSize.isPresent)
        assertNotNull(iface.initPacketMagicHeader)
        assertNotNull(iface.transportPacketMagicHeader)

        assertEquals(1, config.peers.size)
        assertTrue(config.peers.first().endpoint.isPresent)
    }

    @Test
    fun `the captured plain WireGuard configuration still parses, on the same backend`() {
        val config = Config.parse(ByteArrayInputStream(golden("wireguard").toByteArray()))
        assertEquals(listOf("10.9.0.2/32"), config.`interface`.addresses.map { it.toString() })
        assertEquals("vpn.example.com:51820", config.peers.first().endpoint.get().toString())
        assertTrue(config.`interface`.junkPacketCount.isEmpty,
            "plain WireGuard from this panel carries no obfuscation")
    }
}
