package com.skaymer.gryonixnexus.app

import java.io.File
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ManifestClassesTest {
    private val namespace = "com.skaymer.gryonixnexus"

    private fun androidRoot(): File {
        val cwd = requireNotNull(System.getProperty("user.dir")) { "no working directory" }
        var here: File? = File(cwd).absoluteFile
        while (here != null && !File(here, "settings.gradle.kts").isFile) {
            here = here.parentFile
        }
        return requireNotNull(here) { "no settings.gradle.kts above the working directory" }
    }

    /** Our own components, as the manifest names them */
    private fun ownComponents(): List<String> {
        val manifest = File(androidRoot(), "app/src/main/AndroidManifest.xml").readText()
        val tags = Regex("""<(activity|service|receiver|provider)\s[^>]*?android:name="([^"]+)"""")
        return tags.findAll(manifest).map { it.groupValues[2] }
            .map { if (it.startsWith(".")) namespace + it else it }
            .filter { it.startsWith("$namespace.") }
            .toList()
    }

    private fun declared(component: String): Boolean {
        val dir = File(androidRoot(), "app/src/main/kotlin/" + component.substringBeforeLast('.').replace('.', '/'))
        val name = component.substringAfterLast('.')
        val declaration = Regex("""\bclass\s+$name\b""")
        return dir.listFiles { file -> file.extension == "kt" }.orEmpty()
            .any { declaration.containsMatchIn(it.readText()) }
    }

    @Test
    fun `every component the manifest names is a class in the app`() {
        val components = ownComponents()
        assertTrue(components.size >= 3, "the sweep found too few components to mean anything")
        val missing = components.filterNot(::declared)
        assertEquals(
            emptyList<String>(), missing,
            "Android cannot start these: the VPN service or the push receiver silently never runs",
        )
    }
}
