package com.skaymer.gryonixnexus.recipe

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

class SectionsTest {
    private val samples: List<GoldenFixture.Sample> get() = GoldenFixture.samples

    private fun script(fileName: String): List<GoldenFixture.Sample> =
        samples.filter { it.fileName == fileName }

    @TestFactory
    fun `the relay route sync is in the home script and only there`(): List<DynamicTest> {
        val block = RelayRouteSyncSections.install()
        val home = script("setup-home-server.sh")
        assertTrue(home.isNotEmpty(), "the fixture carries no home script")
        return home.map { sample ->
            DynamicTest.dynamicTest(sample.variant) {
                assertTrue(sample.contents.contains(block)) {
                    "the route-sync block is not in the home script verbatim — " +
                        "first line that is absent: " +
                        block.lineSequence().firstOrNull { it !in sample.contents }
                }
            }
        } + script("setup-vps.sh").map { sample ->
            DynamicTest.dynamicTest("${sample.variant}: absent from the relay") {
                assertTrue(!sample.contents.contains(RelayRouteSyncSections.SCRIPT_PATH)) {
                    "the relay's script mentions the home-only route sync"
                }
            }
        }
    }

    @TestFactory
    fun `the agent bootstrap wrapper appears where access is granted`(): List<DynamicTest> {
        val block = AgentBootstrapSections.wrapper("admin")
        return samples.filter { it.fileName.endsWith(".sh") }.map { sample ->
            DynamicTest.dynamicTest("${sample.variant}/${sample.fileName}") {
                val hasAccess = AgentBootstrapSections.SCRIPT_PATH in sample.contents
                if (hasAccess) {
                    assertTrue(sample.contents.contains(block)) {
                        "the bootstrap wrapper is not verbatim — first line that is absent: " +
                            block.lineSequence().firstOrNull { it !in sample.contents }
                    }
                } else {
                    assertTrue(!sample.contents.contains("agent-bootstrap")) {
                        "a script without dashboard access mentions the bootstrap wrapper"
                    }
                }
            }
        }
    }

    @TestFactory
    fun `the metrics collector is in every script`(): List<DynamicTest> =
        samples.filter { it.fileName.endsWith(".sh") }.map { sample ->
            DynamicTest.dynamicTest("${sample.variant}/${sample.fileName}") {
                val language = if (sample.variant.endsWith("-ru")) {
                    com.skaymer.gryonixnexus.catalog.AppLanguage.RU
                } else {
                    com.skaymer.gryonixnexus.catalog.AppLanguage.EN
                }
                val block = MetricsHistorySections.install(language)
                assertTrue(sample.contents.contains(block)) {
                    "the metrics section is not verbatim — first line that is absent: " +
                        block.lineSequence().firstOrNull { it !in sample.contents }
                }
            }
        }
}
