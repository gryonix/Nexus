package com.skaymer.gryonixnexus.app.install

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class InstallPartsTest {
    @Test
    fun withoutTheAgentTheScriptIsTheWholeBar() {
        assertEquals(0.5, InstallParts().fraction(0.5), 1e-9)
    }

    @Test
    fun theBarNeverGoesBackBetweenParts() {
        var parts = InstallParts(throughAgent = true)
        val endOfScript = parts.fraction(1.0)
        parts = parts.copy(scriptDone = true)
        assertEquals(endOfScript, parts.fraction(0.0), 1e-9)
        parts = parts.copy(agentLines = 1)
        assertTrue(parts.fraction(0.0) > endOfScript)
        parts = parts.copy(agentDone = true, servicesTotal = 2, servicesDone = 1)
        assertEquals(0.85, parts.fraction(0.0), 1e-9)
    }

    @Test
    fun theDirectPathFillsOnlyTheServicesShare() {
        val parts = InstallParts(throughAgent = true, scriptDone = true, directServices = true, directStep = 0.5)
        assertEquals(0.85, parts.fraction(0.0), 1e-9)
    }
}
