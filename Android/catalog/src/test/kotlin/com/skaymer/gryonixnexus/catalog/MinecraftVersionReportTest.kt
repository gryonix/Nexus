package com.skaymer.gryonixnexus.catalog

import com.skaymer.gryonixnexus.catalog.services.MinecraftJavaService
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class MinecraftVersionReportTest {
    private fun report(version: String): String {
        val context = ServiceContext(
            domain = "example.com",
            sshUser = "admin",
            settings = ServiceSettings(minecraftJavaVersion = version),
            language = AppLanguage.EN,
        )
        return MinecraftJavaService().reportSteps(context).joinToString("\n")
    }

    @Test
    fun `an unpinned version is named`() {
        assertTrue(
            report("").contains(L10nServices.minecraftVersionFollowsLatest(AppLanguage.EN)),
            "an unpinned version is not named in the report",
        )
    }

    @Test
    fun `a pinned version is not told its world will move`() {
        assertFalse(
            report("1.21.4").contains(L10nServices.minecraftVersionFollowsLatest(AppLanguage.EN)),
            "a pinned version was told its world will move",
        )
    }
}
