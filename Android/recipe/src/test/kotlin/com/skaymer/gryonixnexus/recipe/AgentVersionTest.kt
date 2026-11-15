package com.skaymer.gryonixnexus.recipe

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of the version half of `AgentBundledVersionTests` */
class AgentVersionTest {
    @Test
    fun `november counters sort below the date`() {
        val nov9 = java.time.LocalDate.of(2026, 11, 9)
        assertTrue(AgentVersion.isNewer("26.11.9", than = "26.11.25", today = nov9))
        assertFalse(AgentVersion.isNewer("26.11.25", than = "26.11.9", today = nov9))
        assertTrue(AgentVersion.isNewer("26.11.9-1", than = "26.11.9", today = nov9))
        assertTrue(AgentVersion.isNewer("26.11.10", than = "26.11.9", today = nov9.plusDays(1)))
    }

    @Test
    fun `two-digit components beat single-digit ones`() {
        assertTrue(AgentVersion.isNewer("0.0.82", than = "0.0.9"))
        assertFalse(AgentVersion.isNewer("0.0.9", than = "0.0.82"))
    }

    @Test
    fun `the same version is not an update`() {
        assertFalse(AgentVersion.isNewer("0.0.82", than = "0.0.82"))
    }

    @Test
    fun `earlier components win over later ones`() {
        assertTrue(AgentVersion.isNewer("0.1.0", than = "0.0.99"))
        assertTrue(AgentVersion.isNewer("1.0.0", than = "0.99.99"))
        assertFalse(AgentVersion.isNewer("0.0.99", than = "0.1.0"))
    }

    @Test
    fun `a second build of the day is newer than the first`() {
        assertTrue(AgentVersion.isNewer("26.10.12-1", than = "26.10.12"))
        assertTrue(AgentVersion.isNewer("26.10.12-2", than = "26.10.12-1"))
        assertFalse(AgentVersion.isNewer("26.10.12-9", than = "26.10.13"))
    }

    @Test
    fun `a dated version beats the old numbering`() {
        assertTrue(AgentVersion.isNewer("26.10.11", than = "0.0.237"))
        assertTrue(AgentVersion.isNewer("26.11.1", than = "26.10.31"))
        assertFalse(AgentVersion.isNewer("0.0.237", than = "26.10.11"))
    }

    @Test
    fun `a shorter version is padded rather than ranked below`() {
        assertFalse(AgentVersion.isNewer("0.1", than = "0.1.0"))
        assertFalse(AgentVersion.isNewer("0.1.0", than = "0.1"))
        assertTrue(AgentVersion.isNewer("0.1.1", than = "0.1"))
    }

    /** An unreadable version must not read as "older than everything" */
    @Test
    fun `an unreadable version is never an update`() {
        assertFalse(AgentVersion.isNewer("0.0.82", than = ""))
        assertFalse(AgentVersion.isNewer("", than = "0.0.82"))
        assertFalse(AgentVersion.isNewer("0.0.82", than = "unknown"))
        assertFalse(AgentVersion.isNewer("nightly", than = "0.0.82"))
    }

    @Test
    fun `a suffix does not defeat the comparison`() {
        assertTrue(AgentVersion.isNewer("0.0.83-rc1", than = "0.0.82"))
    }

    @Test
    fun `a version read off a host's stdout still parses`() {
        assertTrue(AgentVersion.isNewer(" 0.0.84 \n", than = "0.0.83"))
        assertFalse(AgentVersion.isNewer(" 0.0.83 \n", than = "0.0.84"))
    }
}

/** The bundled version is the released agent the apps pack */
class AgentBundledVersionTest {
    /** The version the packing script wrote, found by walking up */
    private fun packedVersion(): String {
        var directory: java.io.File? = java.io.File(".").absoluteFile
        while (directory != null) {
            val file = java.io.File(directory, "Apple/App/Resources/agent-src.version")
            if (file.isFile) return file.readText().trim()
            directory = directory.parentFile
        }
        throw AssertionError("no Apple/App/Resources/agent-src.version above ${java.io.File(".").absolutePath}")
    }

    @Test
    fun `the bundled version is the packed one`() {
        val packed = packedVersion()
        assertEquals(
            packed,
            AgentBootstrapSections.BUNDLED_VERSION,
            "the app says it carries ${AgentBootstrapSections.BUNDLED_VERSION} but packs $packed — " +
                "the app carries the agent on main of nexus-agent; set BUNDLED_VERSION to that",
        )
    }

    /** The harness must be able to fail */
    @Test
    fun `the harness actually reads the packed version`() {
        val packed = packedVersion()
        assertTrue(packed.isNotEmpty() && packed.first().isDigit(), "agent-src.version holds no version: $packed")
    }
}
