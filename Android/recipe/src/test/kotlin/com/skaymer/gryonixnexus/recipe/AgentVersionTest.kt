package com.skaymer.gryonixnexus.recipe

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of the version half of `AgentBundledVersionTests` */
class AgentVersionTest {
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

/**
 * **The app's idea of which agent it carries has to be the crate's own.**
 *
 * The Kotlin twin of `AgentBundledVersionTests`, and it reads the SAME manifest
 * the Swift one does rather than the Swift constant: two apps pinned to one
 * source cannot drift apart, whereas one pinned to the other would follow it
 * into a mistake.
 *
 * The bootstrap decides whether to rebuild by comparing the constant against
 * `gryonixnexusd version` on the host, and the dashboard uses it to decide whether
 * to offer an update at all. A constant that quietly lags the crate makes the
 * app either offer an update that changes nothing, or — the expensive one — stay
 * silent about one that matters, on every host in the fleet, with nothing on
 * screen suggesting anything is wrong.
 */
class AgentBundledVersionTest {
    /**
     * The crate manifest, found by walking UP from the working directory rather
     * than by a fixed relative path: Gradle runs a test with the module
     * directory as its own, and a path that silently finds nothing is the
     * failure this project has hit five times.
     */
    private fun cargoManifest(): String {
        var directory: java.io.File? = java.io.File(".").absoluteFile
        while (directory != null) {
            val manifest = java.io.File(directory, "Server/gryonixnexusd/Cargo.toml")
            if (manifest.isFile) {
                val text = manifest.readText()
                assertTrue(text.isNotEmpty(), "found the manifest but it is empty: $manifest")
                return text
            }
            directory = directory.parentFile
        }
        throw AssertionError("no Server/gryonixnexusd/Cargo.toml above ${java.io.File(".").absolutePath}")
    }

    /**
     * `version = "x.y.z"` from the `[package]` table, and only from there.
     *
     * **Not "the first bare `version =` line in the file", which is what this
     * started as.** A negative control pointed the reader at `Cargo.lock` — a
     * file that also says `name = "gryonixnexusd"` — and it cheerfully returned
     * some dependency's version while the harness check that was supposed to
     * catch a wrong file stayed green. Reading the section makes a wrong file
     * answer nothing at all, which is the only answer a wrong file may give.
     */
    private fun crateVersion(manifest: String): String? {
        var inPackage = false
        for (line in manifest.lineSequence()) {
            val trimmed = line.trim()
            if (trimmed.startsWith("[")) {
                inPackage = trimmed == "[package]"
                continue
            }
            if (inPackage && trimmed.startsWith("version = \"")) {
                return trimmed.removePrefix("version = \"").removeSuffix("\"")
            }
        }
        return null
    }

    @Test
    fun `the bundled version is the crate version`() {
        val crate = crateVersion(cargoManifest())
        assertTrue(crate != null, "no top-level `version = \"…\"` line in Cargo.toml")
        assertEquals(
            crate,
            AgentBootstrapSections.BUNDLED_VERSION,
            "the app says it carries ${AgentBootstrapSections.BUNDLED_VERSION} but the crate is $crate — " +
                "bump AgentBootstrapSections.BUNDLED_VERSION together with Cargo.toml",
        )
    }

    /** The harness must be able to fail */
    @Test
    fun `the harness actually reads the manifest`() {
        val manifest = cargoManifest()
        assertTrue(manifest.contains("name = \"gryonixnexusd\""), "this is not the agent's manifest")
        assertTrue(manifest.contains("[package]"), "this is not a Cargo manifest")
        assertTrue(crateVersion(manifest) != null, "no version in the [package] table")
    }
}
