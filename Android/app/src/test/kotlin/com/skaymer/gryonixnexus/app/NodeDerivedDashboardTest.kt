package com.skaymer.gryonixnexus.app

import java.io.File
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `NodeDerivedDashboardTests` */
class NodeDerivedDashboardTest {
    /** Reading the stored enum off a value */
    private val read = ".topology"

    private val generationAndCreationTime = setOf(
        "ConfiguratorWizard.kt",
        "ConfiguratorViewModel.kt",
        "ConfiguratorForm.kt",
        "ScenarioOption.kt",
        "ConfiguratorHistory.kt",
        // Asks the configurator's questions before anything is installed.
        "ServiceQuestions.kt",
        "DeploymentRecorder.kt",
        // Routes a scenario choice into the configurator.
        "AppShell.kt",
        "Deployment.kt",
    )

    private fun runtimeRoots(): List<File> {
        var here = File(System.getProperty("user.dir")).absoluteFile
        while (here.parentFile != null && !File(here, "settings.gradle.kts").isFile) {
            here = here.parentFile
        }
        return listOf(
            File(here, "app/src/main/kotlin"),
            File(here, "servercontrol/src/main/kotlin"),
        )
    }

    private fun sources(root: File): List<File> =
        root.walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()

    @Test
    fun `no screen that manages a running deployment asks the topology enum`() {
        var scanned = 0
        val offenders = mutableListOf<String>()

        for (root in runtimeRoots()) {
            assertTrue(root.isDirectory, "the sweep points at nothing: ${root.path}")
            for (file in sources(root)) {
                scanned++
                if (file.name in generationAndCreationTime) continue
                file.readLines().forEachIndexed { index, line ->
                    // Prose about the rule is not a use of it.
                    if (read in line && !line.trimStart().startsWith("//") &&
                        !line.trimStart().startsWith("*")
                    ) {
                        offenders += "${file.name}:${index + 1}  ${line.trim()}"
                    }
                }
            }
        }

        assertTrue(scanned > 100, "the source sweep found almost nothing ($scanned files) — check the paths")
        assertEquals(
            emptyList<String>(), offenders,
            """
            These ask a two-value enum a question a deployment with three machines cannot
            answer. Ask the machines instead: isMultiHost, hasRelayIngress, hasHomeHost,
            servicesHost, hostRunning, workerHosts, nodes. If the read really is about the
            install SHAPE rather than a running deployment, name the file in
            generationAndCreationTime and say why:
            ${offenders.joinToString("\n")}
            """.trimIndent(),
        )
    }

    @Test
    fun `the derived questions are the ones in use`() {
        val counts = mutableMapOf<String, Int>()
        for (root in runtimeRoots()) {
            for (file in sources(root)) {
                if (file.name == "Deployment.kt") continue
                for (line in file.readLines()) {
                    val code = line.trimStart()
                    if (code.startsWith("//") || code.startsWith("*") || code.startsWith("/*")) continue
                    for (helper in listOf(
                        "isMultiHost", "hasRelayIngress", "hasHomeHost",
                        "servicesHost", "hostRunning", "workerHosts",
                    )) {
                        counts[helper] = (counts[helper] ?: 0) + line.split(helper).size - 1
                    }
                }
            }
        }
        for (helper in listOf(
            "isMultiHost", "hasRelayIngress", "hasHomeHost",
            "servicesHost", "hostRunning", "workerHosts",
        )) {
            assertTrue((counts[helper] ?: 0) > 0,
                       "$helper is declared and called nowhere — a dead seam. Counts: $counts")
        }
    }
}
