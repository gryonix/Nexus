package com.skaymer.gryonixnexus.profile

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class XrayConfigurationGoldenTest {
    private val json = Json { ignoreUnknownKeys = false }
    private val access = LocalProxyAccess(40123, "session-user", "session-pass")

    private fun golden(): JsonArray {
        val text = checkNotNull(javaClass.getResourceAsStream("/swift-xray-configs.json")) {
            "the golden is missing — capture it with `swift run xray-config-golden`"
        }.bufferedReader().readText()
        val rows = json.parseToJsonElement(text) as JsonArray
        assertTrue(rows.size >= 6, "the golden is implausibly short: ${rows.size} rows")
        return rows
    }

    @Test
    fun `every link becomes the configuration Swift builds`() {
        for (row in golden()) {
            val link = row.jsonObject["link"]!!.jsonPrimitive.content
            val expected = row.jsonObject["config"] as JsonObject
            val built = XrayConfiguration.document(link, access)
            assertEquals(expected, built, "the configuration for <$link>")
        }
    }

    /** The seam between the two halves of this datapath */
    @Test
    fun `the socks port is the one tun2socks dials`() {
        val yaml = Tun2SocksConfiguration.yaml(access)
        assertTrue(yaml.contains("port: ${access.port}"), "the two halves have to name the same port")
        assertTrue(yaml.contains("tcp-buffer-size: 4096"), "each connection keeps a small buffer")
        assertTrue(yaml.contains("task-stack-size: 24576"))
        assertTrue(yaml.contains("udp-read-write-timeout: 10000"), "silent UDP flows close soon")
        assertTrue(yaml.contains("max-session-count: 128"))
        assertTrue(yaml.contains("username: ${access.username}"))
        assertTrue(yaml.contains("password: ${access.password}"))
        assertTrue(
            yaml.contains("ipv4: ${Tun2SocksConfiguration.ADDRESS}"),
            "the address the system routes at is the address lwIP builds on",
        )
    }

    @Test
    fun `every session gets its own login`() {
        val first = LocalProxyAccess.random()
        val second = LocalProxyAccess.random()
        assertTrue(first.username != second.username && first.password != second.password)
        assertEquals(32, first.username.length)
        assertTrue(first.port in 1024..65535)
    }
}
