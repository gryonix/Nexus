package com.skaymer.gryonixnexus.app.agent

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class AgentHealthTextTests {
    @Test
    fun `an unset start time has no text`() {
        assertNull(AgentHealthText.startedAt(0))
        assertEquals(1_700_000_000_000, AgentHealthText.startedAt(1_700_000_000_000))
    }

    @Test
    fun `negative sizes print as zero`() {
        assertEquals(0, AgentHealthText.nonNegative(-5))
        assertEquals(42, AgentHealthText.nonNegative(42))
    }

    @Test
    fun `module detail skips a missing part`() {
        assertEquals("26.11.7 · 4 MB", AgentHealthText.moduleDetail("26.11.7", "4 MB"))
        assertEquals("4 MB", AgentHealthText.moduleDetail("", "4 MB"))
    }
}
