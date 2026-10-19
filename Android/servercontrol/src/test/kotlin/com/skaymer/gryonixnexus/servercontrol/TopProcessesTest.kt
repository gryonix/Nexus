package com.skaymer.gryonixnexus.servercontrol

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class TopProcessesTest {
    private fun fixture(name: String): String =
        requireNotNull(javaClass.getResource("/processes/$name")) { name }.readText()

    @Test
    fun `real top output reads the second sample without itself`() {
        val samples = TopProcesses.parse(fixture("top-orion.txt"))
        assertTrue(samples.size > 150)
        assertFalse(samples.any { it.command.startsWith("top -b") })
        val hass = samples.first { it.command.contains("homeassistant") }
        assertEquals(1.0, hass.cpu)
        assertEquals(216_960L, hass.memoryKiB)
        assertTrue(samples.first().command.startsWith("/usr/bin/dbus-daemon"))
    }

    @Test
    fun `friendly rows group and sort by memory`() {
        val samples = TopProcesses.parse(fixture("top-orion.txt"))
        assertEquals("Home Assistant", TopProcesses.rows(samples, friendly = true, byMemory = true).first().name)
        val all = TopProcesses.rows(samples, friendly = true, byMemory = true, limit = Int.MAX_VALUE)
        assertEquals(1, all.count { it.name == "Linux" })
        assertTrue(all.first { it.name == "Linux" }.count > 50)
        val system = TopProcesses.rows(samples, friendly = false, byMemory = true).first()
        assertEquals("python3", system.name)
        assertEquals("python3 -P -m homeassistant --config /config", system.detail)
    }

    @Test
    fun `names match the shared table`() {
        Json.parseToJsonElement(fixture("process-names.json")).jsonArray.forEach { pair ->
            val command = pair.jsonArray[0].jsonPrimitive.content
            val expected = pair.jsonArray[1].let { if (it is JsonNull) null else it.jsonPrimitive.content }
            assertEquals(expected, ProcessNames.friendly(command), command)
        }
    }
}
