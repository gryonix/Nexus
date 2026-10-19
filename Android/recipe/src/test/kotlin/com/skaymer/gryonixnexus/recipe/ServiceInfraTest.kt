package com.skaymer.gryonixnexus.recipe

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

class ServiceInfraTest {
    /** The half of a run that installs the services */
    private fun mailHostScript(variant: String): GoldenFixture.Sample? =
        GoldenFixture.samples.firstOrNull {
            it.variant == variant && it.fileName.endsWith(".sh") &&
                it.fileName != "setup-vps.sh"
        }

    private val runs = GoldenFixture.variants.mapNotNull { variant ->
        mailHostScript(variant.name)?.let { variant to it }
    }

    @TestFactory
    fun `every service infrastructure section is in the Swift script`(): List<DynamicTest> {
        assertTrue(runs.isNotEmpty(), "no dumped variant has a mail-host script")
        return runs.flatMap { (variant, script) ->
            val sections = ServiceInfraSections.allSections(GoldenFixture.context(variant))
            if (sections.isEmpty()) {
                return@flatMap listOf(DynamicTest.dynamicTest("${variant.name}: no services") {
                    assertTrue(variant.services.isEmpty()) {
                        "${variant.name} selects ${variant.services}, yet built no sections"
                    }
                    assertTrue("get.docker.com" !in script.contents) {
                        "the Swift script installs docker, this side built nothing"
                    }
                })
            }
            sections.mapIndexed { index, section ->
                val label = section.lineSequence().first().take(60)
                DynamicTest.dynamicTest("${variant.name}/[$index] $label") {
                    assertTrue(script.contents.contains(section)) {
                        "${script.fileName}: this section is not verbatim — " +
                            "first line that is absent: " +
                            section.lineSequence().firstOrNull { it !in script.contents }
                    }
                }
            }
        }
    }

    @TestFactory
    fun `the standalone report matches the Swift text`(): List<DynamicTest> =
        runs.map { (variant, script) ->
            DynamicTest.dynamicTest("${variant.name}/${script.fileName}") {
                val context = GoldenFixture.context(variant)
                val report = ServiceInfraSections.standaloneReport(
                    context, extraLines = extraLines(script.contents, context)
                )
                assertTrue(script.contents.contains(report)) {
                    "${script.fileName}: the report is not verbatim — " +
                        "first line that is absent: " +
                        report.lineSequence().firstOrNull { it !in script.contents }
                }
            }
        }

    private fun extraLines(script: String, context: MailContext): List<String> {
        val domainLine = "echo \"${L10nScripts.domainLabel(context.language)}${context.domainName}\""
        val after = script.substringAfter("$domainLine\n", "")
        check(after.isNotEmpty()) { "the report's domain line is not in the script" }
        return after.lineSequence().takeWhile { it != "echo" }
            .map { it.removePrefix("echo \"").removeSuffix("\"") }
            .toList()
    }

    @TestFactory
    fun `the report names a passphrase exactly where Swift does`(): List<DynamicTest> =
        runs.map { (variant, script) ->
            DynamicTest.dynamicTest("${variant.name}/${script.fileName}") {
                val context = GoldenFixture.context(variant)
                val reported = L10nScripts.backupPassphraseLabel(context.language) in script.contents
                assertEquals(reported, ServiceInfraSections.hostNeedsBackupPassphrase(context),
                             "${script.fileName}: the two sides disagree about the passphrase")
            }
        }

    /** The generation section, wherever the Swift run wrote one */
    @TestFactory
    fun `the passphrase section matches wherever Swift writes one`(): List<DynamicTest> =
        runs.map { (variant, script) ->
            DynamicTest.dynamicTest("${variant.name}/${script.fileName}") {
                val context = GoldenFixture.context(variant)
                val section = BackupControlSections.passphraseSection(
                    context.allSelectedServices, context.serviceContext
                )
                if (GENERATED in script.contents) {
                    assertTrue(script.contents.contains(section)) {
                        "the passphrase section is not verbatim — first line that is absent: " +
                            section.lineSequence().firstOrNull { it !in script.contents }
                    }
                } else {
                    assertTrue(section.isEmpty() || variant.access == null) {
                        "${script.fileName}: this side would generate a passphrase the Swift run does not"
                    }
                }
            }
        }

    @TestFactory
    fun `the no-access route names no passphrase and writes none`(): List<DynamicTest> =
        runs.filter { (variant, _) -> variant.access == null }
            .map { (variant, script) ->
                val context = GoldenFixture.context(variant)
                DynamicTest.dynamicTest("${variant.name}/${script.fileName}") {
                    assertTrue(GENERATED !in script.contents) {
                        "${script.fileName}: no backup wrapper is installed without dashboard access"
                    }
                    assertTrue(L10nScripts.backupPassphraseLabel(context.language) !in
                                   script.contents) {
                        "${script.fileName}: the report asks the owner to keep an empty passphrase"
                    }
                    assertTrue(!ServiceInfraSections.hostNeedsBackupPassphrase(context)) {
                        "${script.fileName}: this side would name a passphrase Swift does not"
                    }
                }
            }

    private companion object {
        /** The generation section's own log line */
        const val GENERATED = "log \"Backup passphrase\""
    }
}
