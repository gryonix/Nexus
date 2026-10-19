package com.skaymer.gryonixnexus.app.shell

import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class AppIconsTests {
    private val manifest = File("src/main/AndroidManifest.xml").readText()

    private fun aliasBlock(icon: AppIcon): String {
        val name = "android:name=\"" + icon.alias.removePrefix("com.skaymer.gryonixnexus") + "\""
        val start = manifest.indexOf(name)
        assertTrue(start >= 0, "${icon.raw} has no launcher alias")
        return manifest.substring(start, manifest.indexOf("</activity-alias>", start))
    }

    @Test
    fun `every colour has a launcher entry and only blue starts enabled`() {
        val enabled = AppIcon.entries.filter { aliasBlock(it).contains("android:enabled=\"true\"") }
        assertEquals(listOf(AppIcon.BLUE), enabled)
        AppIcon.entries.forEach { assertTrue(aliasBlock(it).contains("category.LAUNCHER"), it.raw) }
    }

    @Test
    fun `every colour has its artwork in every density`() {
        val res = File("src/main/res")
        for (icon in AppIcon.entries) {
            assertTrue(File(res, "drawable-nodpi/icon_preview_${icon.raw}.png").exists(), "${icon.raw} preview")
            if (icon == AppIcon.BLUE) continue
            assertTrue(File(res, "mipmap-anydpi-v26/ic_launcher_${icon.raw}.xml").exists(), "${icon.raw} adaptive")
            for (density in listOf("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi")) {
                assertTrue(File(res, "mipmap-$density/ic_launcher_${icon.raw}_foreground.png").exists(),
                    "${icon.raw} $density")
            }
        }
    }

    @Test
    fun `the main activity no longer claims the launcher itself`() {
        val main = manifest.substringAfter("android:name=\".app.MainActivity\"").substringBefore("</activity>")
        assertTrue(!main.contains("category.LAUNCHER"), "two launcher entries would show two icons")
    }
}
