package com.skaymer.gryonixnexus.app

import java.io.File
import javax.imageio.ImageIO
import kotlin.math.hypot
import kotlin.math.roundToInt
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class LauncherIconTest {
    private fun repoRoot(): File {
        val cwd = requireNotNull(System.getProperty("user.dir")) { "no working directory" }
        var here: File? = File(cwd).absoluteFile
        while (here != null && !File(here, "settings.gradle.kts").isFile) {
            here = here.parentFile
        }
        val android = requireNotNull(here) { "no settings.gradle.kts above the working directory" }
        return requireNotNull(android.parentFile) { "no repository above ${android.path}" }
    }

    private fun res(): File = File(repoRoot(), "Android/app/src/main/res")

    /** dp per density bucket, as Android defines them */
    private val densities = listOf(
        "mdpi" to 1.0, "hdpi" to 1.5, "xhdpi" to 2.0, "xxhdpi" to 3.0, "xxxhdpi" to 4.0,
    )

    private val canvasDp = 108.0
    private val safeDiameterDp = 66.0

    private fun inkReach(image: java.awt.image.BufferedImage): Pair<Double, String> {
        val centre = image.width / 2.0
        var worst = 0.0
        var worstAt = ""
        for (y in 0 until image.height) {
            for (x in 0 until image.width) {
                val pixel = image.getRGB(x, y)
                if ((pixel ushr 24) <= 8) continue
                if ((pixel shr 16 and 0xFF) > 200) continue
                val distance = hypot(x + 0.5 - centre, y + 0.5 - centre)
                if (distance > worst) {
                    worst = distance
                    worstAt = "($x, $y)"
                }
            }
        }
        return worst to worstAt
    }

    @Test
    fun `the app claims an icon at all`() {
        val manifest = File(repoRoot(), "Android/app/src/main/AndroidManifest.xml").readText()
        assertTrue(
            manifest.contains("android:icon=\"@mipmap/ic_launcher\""),
            "the manifest does not name an icon — the launcher draws the default robot",
        )
        assertTrue(
            manifest.contains("android:roundIcon=\"@mipmap/ic_launcher_round\""),
            "no round icon: launchers that ask for one fall back to the square bitmap",
        )
        val adaptive = File(res(), "mipmap-anydpi-v26/ic_launcher.xml")
        assertTrue(adaptive.isFile, "no adaptive icon at ${adaptive.path}")
        val xml = adaptive.readText()
        assertTrue(
            xml.contains("@color/ic_launcher_background"),
            "the adaptive icon has no background layer — the mask would cut into nothing",
        )
        assertTrue(
            xml.contains("@mipmap/ic_launcher_foreground"),
            "the adaptive icon has no foreground layer",
        )
    }

    @Test
    fun `every density carries both bitmaps at its own size`() {
        for ((bucket, scale) in densities) {
            val foreground = File(res(), "mipmap-$bucket/ic_launcher_foreground.png")
            assertTrue(foreground.isFile, "missing ${foreground.path}")
            val image = ImageIO.read(foreground)
            val expected = (canvasDp * scale).roundToInt()
            assertEquals(expected, image.width, "$bucket foreground is the wrong width")
            assertEquals(expected, image.height, "$bucket foreground is the wrong height")

            val legacy = File(res(), "mipmap-$bucket/ic_launcher.png")
            assertTrue(legacy.isFile, "missing ${legacy.path}")
            val square = ImageIO.read(legacy)
            assertEquals((48 * scale).roundToInt(), square.width, "$bucket legacy is the wrong size")
        }
    }

    @Test
    fun `no painted pixel of the foreground falls outside the safe circle`() {
        for ((bucket, scale) in densities) {
            val image = ImageIO.read(File(res(), "mipmap-$bucket/ic_launcher_foreground.png"))
            val side = canvasDp * scale
            val safeRadius = side * (safeDiameterDp / canvasDp) / 2
            val (worst, worstAt) = inkReach(image)
            assertTrue(worst > 0, "$bucket foreground is empty — nothing is drawn at all")
            assertTrue(
                worst <= safeRadius + 1,
                "$bucket: ink at $worstAt is ${"%.1f".format(worst)}px from the centre, " +
                    "outside the ${"%.1f".format(safeRadius)}px circle every mask is " +
                    "guaranteed to show — this icon loses that corner on a round launcher",
            )
        }
    }

    @Test
    fun `the artwork fills the circle it is allowed`() {
        val image = ImageIO.read(File(res(), "mipmap-xxxhdpi/ic_launcher_foreground.png"))
        val side = canvasDp * 4
        val safeRadius = side * (safeDiameterDp / canvasDp) / 2
        val (reach, _) = inkReach(image)
        assertTrue(
            reach >= safeRadius * 0.7,
            "the artwork reaches only ${"%.2f".format(reach / safeRadius)} of the circle it is " +
                "allowed — it will read as a small picture in a big empty plate",
        )
    }
}
