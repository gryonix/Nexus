package com.skaymer.gryonixnexus.agentcontrol

import com.skaymer.gryonixnexus.catalog.ServiceSettings
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** The agent gets the same settings from both apps */
class AgentInstallSettingsParityTest {
    @Test
    fun `the default settings map matches the Swift one key for key`() {
        val swift = javaClass.getResource("/swift-agent-install-settings.tsv")!!.readText()
            .lines().filter { it.isNotEmpty() }
            .associate { it.substringBefore('\t') to it.substringAfter('\t') }
        val kotlin = AgentInstallSettings.map(ServiceSettings())
        assertEquals((swift.keys - kotlin.keys).sorted(), emptyList<String>(), "keys Android does not send")
        assertEquals((kotlin.keys - swift.keys).sorted(), emptyList<String>(), "keys iOS does not send")
        assertEquals(swift.filter { kotlin[it.key] != it.value }.keys.sorted(), emptyList<String>(), "values that differ")
    }
}
