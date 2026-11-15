package com.skaymer.gryonixnexus.servercontrol

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class SystemdShowParserTest {
    @Test
    fun `only loaded units become rows`() {
        val output = """
            Id=odio-api.service
            LoadState=loaded
            ActiveState=active

            Id=mympd.service
            LoadState=not-found
            ActiveState=inactive

            Id=mpd.service
            LoadState=loaded
            ActiveState=failed
        """.trimIndent()
        val rows = SystemdShowParser.parse(output)
        assertEquals(listOf("odio-api.service", "mpd.service"), rows.map { it.name })
        assertEquals(listOf(HealthLevel.OK, HealthLevel.CRITICAL), rows.map { it.health })
    }
}
