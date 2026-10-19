package com.skaymer.gryonixnexus.app

import java.io.File
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class BrandMarkParityTest {
    private fun repoRoot(): File {
        val cwd = requireNotNull(System.getProperty("user.dir")) { "no working directory" }
        var here: File? = File(cwd).absoluteFile
        while (here != null && !File(here, "settings.gradle.kts").isFile) {
            here = here.parentFile
        }
        // `settings.gradle.kts` is `Android/`; the repository is its parent.
        val android = requireNotNull(here) { "no settings.gradle.kts above the working directory" }
        return requireNotNull(android.parentFile) { "no repository above ${android.path}" }
    }

    private val androidMark: File
        get() = File(repoRoot(), "Android/app/src/main/res/drawable/tab_icon_logo.xml")

    private val appleMark: File
        get() = File(
            repoRoot(),
            "Apple/Shared/BrandMarks.xcassets/TabIconLogo.imageset/TabIconLogo.svg",
        )

    private val androidGlobe: File
        get() = File(repoRoot(), "Android/app/src/main/res/drawable/tab_icon_globe.xml")

    private val appleGlobe: File
        get() = File(
            repoRoot(),
            "Apple/Shared/BrandMarks.xcassets/TabIconGlobe.imageset/TabIconGlobe.svg",
        )

    private fun attributes(pattern: String, text: String): List<String> =
        Regex(pattern).findAll(text).map { it.groupValues[1] }.toList()

    /** Whitespace inside path data is formatting, not drawing */
    private fun canonical(path: String): String = path.trim().replace(Regex("\\s+"), " ")

    @Test
    fun `the mark is the same drawing on both platforms`() {
        assertTrue(androidMark.isFile, "the sweep points at nothing: ${androidMark.path}")
        assertTrue(appleMark.isFile, "the sweep points at nothing: ${appleMark.path}")

        val android = androidMark.readText()
        val apple = appleMark.readText()

        val androidPaths = attributes("""android:pathData="([^"]+)"""", android).map(::canonical)
        val applePaths = attributes("""\bd="([^"]+)"""", apple).map(::canonical)

        assertTrue(applePaths.isNotEmpty(), "no paths read out of ${appleMark.name}")
        assertEquals(applePaths, androidPaths, "the two marks are no longer one drawing")
    }

    @Test
    fun `the mark carries the same stroke weight on both platforms`() {
        val androidWidths = attributes(
            """android:strokeWidth="([\d.]+)"""",
            androidMark.readText(),
        )
        val appleWidths = attributes("""stroke-width="([\d.]+)"""", appleMark.readText())

        assertTrue(appleWidths.isNotEmpty(), "no stroke widths read out of ${appleMark.name}")
        assertEquals(setOf("340"), appleWidths.toSet(), "the Apple mark changed weight")
        assertEquals(appleWidths, androidWidths, "the two marks are no longer one weight")
    }

    @Test
    fun `the globe is the mark without its shield, on both platforms`() {
        assertTrue(androidGlobe.isFile, "the sweep points at nothing: ${androidGlobe.path}")
        assertTrue(appleGlobe.isFile, "the sweep points at nothing: ${appleGlobe.path}")

        val markPaths = attributes("""android:pathData="([^"]+)"""", androidMark.readText())
            .map(::canonical)
        val globePaths = attributes("""android:pathData="([^"]+)"""", androidGlobe.readText())
            .map(::canonical)
        assertTrue(globePaths.isNotEmpty(), "no paths read out of ${androidGlobe.name}")
        assertEquals(
            markPaths.drop(1),
            globePaths,
            "the globe is no longer the mark's own globe",
        )

        val appleGlobePaths = attributes("""\bd="([^"]+)"""", appleGlobe.readText()).map(::canonical)
        assertEquals(globePaths, appleGlobePaths, "the two globes are no longer one drawing")
    }

    @Test
    fun `both glyphs come to the same line on screen`() {
        fun androidRatio(file: File): Double {
            val text = file.readText()
            val widths = attributes("""android:strokeWidth="([\d.]+)"""", text)
            assertTrue(widths.isNotEmpty(), "no stroke widths read out of ${file.name}")
            assertEquals(1, widths.toSet().size, "${file.name} draws two weights")
            val viewport = attributes("""android:viewportWidth="([\d.]+)"""", text).single()
            return widths.first().toDouble() / viewport.toDouble()
        }

        fun appleRatio(file: File): Double {
            val text = file.readText()
            val widths = attributes("""stroke-width="([\d.]+)"""", text)
            assertTrue(widths.isNotEmpty(), "no stroke widths read out of ${file.name}")
            assertEquals(1, widths.toSet().size, "${file.name} draws two weights")
            val side = Regex("""viewBox="-?[\d.]+ -?[\d.]+ ([\d.]+) [\d.]+"""")
                .find(text)
                ?.groupValues
                ?.get(1)
                ?: error("no viewBox in ${file.name}")
            return widths.first().toDouble() / side.toDouble()
        }

        val tolerance = 0.001
        val mark = androidRatio(androidMark)
        assertEquals(mark, appleRatio(appleMark), tolerance, "the mark's line differs by platform")
        assertEquals(mark, androidRatio(androidGlobe), tolerance, "the globe thins when it opens")
        assertEquals(
            mark,
            appleRatio(appleGlobe),
            tolerance,
            "the Apple globe's line is not the mark's",
        )
    }

    @Test
    fun `the globes stand on one canvas`() {
        val globe = androidGlobe.readText()
        val viewBox = Regex("""viewBox="(-?[\d.]+) (-?[\d.]+) ([\d.]+) ([\d.]+)"""")
            .find(appleGlobe.readText())
            ?.groupValues
            ?: error("no viewBox in ${appleGlobe.name}")
        val (minX, minY, width, height) = viewBox.drop(1).map(String::toDouble)

        assertEquals(
            width,
            attributes("""android:viewportWidth="([\d.]+)"""", globe).single().toDouble(),
            "the globes' canvases are different widths",
        )
        assertEquals(
            height,
            attributes("""android:viewportHeight="([\d.]+)"""", globe).single().toDouble(),
            "the globes' canvases are different heights",
        )
        assertEquals(
            -minX,
            attributes("""android:translateX="(-?[\d.]+)"""", globe).single().toDouble(),
            "the globes are offset differently in x",
        )
        assertEquals(
            -minY,
            attributes("""android:translateY="(-?[\d.]+)"""", globe).single().toDouble(),
            "the globes are offset differently in y",
        )
    }

    @Test
    fun `the two canvases describe the same square`() {
        val android = androidMark.readText()
        val apple = appleMark.readText()

        // The author's canvas: `viewBox="<minX> <minY> <side> <side>"`.
        val viewBox = Regex("""viewBox="(-?[\d.]+) (-?[\d.]+) ([\d.]+) ([\d.]+)"""")
            .find(apple)
            ?.groupValues
            ?: error("no viewBox in ${appleMark.name}")
        val (minX, minY, width, height) = viewBox.drop(1).map(String::toDouble)

        val viewportWidth = attributes("""android:viewportWidth="([\d.]+)"""", android).single()
        val viewportHeight = attributes("""android:viewportHeight="([\d.]+)"""", android).single()
        val translateX = attributes("""android:translateX="(-?[\d.]+)"""", android).single()
        val translateY = attributes("""android:translateY="(-?[\d.]+)"""", android).single()

        assertEquals(width, viewportWidth.toDouble(), "the canvas is a different width")
        assertEquals(height, viewportHeight.toDouble(), "the canvas is a different height")
        assertEquals(-minX, translateX.toDouble(), "the canvas is offset differently in x")
        assertEquals(-minY, translateY.toDouble(), "the canvas is offset differently in y")
    }
}
