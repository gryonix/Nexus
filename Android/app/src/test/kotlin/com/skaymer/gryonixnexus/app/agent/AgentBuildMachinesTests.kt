package com.skaymer.gryonixnexus.app.agent

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class AgentBuildMachinesTests {
    @Test
    fun `one machine keeps its lines as they are`() {
        val machines = AgentBuildMachines(listOf("VPS"))
        assertEquals("Compiling serde", machines.line("Compiling serde", "VPS"))
    }

    @Test
    fun `several machines name every line`() {
        val machines = AgentBuildMachines(listOf("VPS", "Local"))
        assertEquals("Local: Compiling serde", machines.line("Compiling serde", "Local"))
    }

    @Test
    fun `the summary says which machine is still building`() {
        var clock = 1_000_000L
        val machines = AgentBuildMachines(listOf("VPS", "Local"), now = { clock })
        machines.started("VPS")
        machines.started("Local")
        machines.finished("VPS", ok = true)
        clock += 20_000
        assertEquals("VPS: done · Local: building", machines.summary())
        clock += 4 * 60_000
        assertEquals("VPS: done · Local: building, 4 min", machines.summary())
        assertTrue(machines.anyBuilding)
        machines.finished("Local", ok = false)
        assertEquals("VPS: done · Local: failed", machines.summary())
        assertFalse(machines.anyBuilding)
    }
}
