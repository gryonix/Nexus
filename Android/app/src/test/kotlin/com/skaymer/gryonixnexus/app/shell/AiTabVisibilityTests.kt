package com.skaymer.gryonixnexus.app.shell

import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class AiTabVisibilityTests {
    private fun visible(aiOn: Boolean) = ShellSections.visible(
        AppTab.entries, MetricsPlacement.BOTH.raw, VPNPlacement.BOTH.raw,
        ContainersPlacement.BOTH.raw, TerminalPlacement.BOTH.raw, aiOn,
    )

    @Test
    fun `the AI tab is on the bar only while the module is on`() {
        assertFalse(visible(false).contains(AppTab.AI))
        assertTrue(visible(true).contains(AppTab.AI))
    }

    @Test
    fun `the AI module is off by default`() {
        assertFalse(ModuleSettings(InMemorySettingsStore()).isOn(AppModule.AI))
    }
}
