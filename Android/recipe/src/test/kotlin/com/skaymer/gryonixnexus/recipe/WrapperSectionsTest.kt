package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.ServiceContext
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

class WrapperSectionsTest {
    private fun servicesHostScript(variant: String): GoldenFixture.Sample? =
        GoldenFixture.samples.firstOrNull {
            it.variant == variant && it.fileName.endsWith(".sh") &&
                it.fileName != "setup-vps.sh"
        }

    private val runs = GoldenFixture.variants.mapNotNull { variant ->
        val access = GoldenFixture.input(variant).dashboardAccess ?: return@mapNotNull null
        servicesHostScript(variant.name)?.let { Triple(variant, access, it) }
    }

    private fun accessContext(variant: GoldenFixture.GoldenVariant): ServiceContext =
        GoldenFixture.context(variant).serviceContext.copy(
            sshUser = GoldenFixture.input(variant).dashboardAccess!!.sshUser
        )

    private fun wrapper(variant: GoldenFixture.GoldenVariant): String {
        val context = GoldenFixture.context(variant)
        return BackupControlSections.wrapper(
            access = GoldenFixture.input(variant).dashboardAccess!!,
            services = context.allSelectedServices,
            context = accessContext(variant),
            language = context.language
        )
    }

    @TestFactory
    fun `the backup wrapper is in the Swift script verbatim`(): List<DynamicTest> {
        assertTrue(runs.isNotEmpty(), "no dumped variant grants dashboard access")
        return runs.map { (variant, _, script) ->
            DynamicTest.dynamicTest("${variant.name}/${script.fileName}") {
                val context = GoldenFixture.context(variant)
                val hasBackup = context.allSelectedServices.any {
                    it.actions(context.serviceContext).backup != null
                }
                val section = wrapper(variant)
                if (!hasBackup) {
                    assertTrue("EOF_BACKUP_CTL" !in script.contents) {
                        "${script.fileName} writes the wrapper for a host with no backups"
                    }
                    return@dynamicTest
                }
                if (!script.contents.contains(section)) {
                    val out = java.io.File("build/recipe-mismatch")
                    out.mkdirs()
                    java.io.File(out, "${variant.name}__backup-ctl.sh").writeText(section)
                }
                assertTrue(script.contents.contains(section)) {
                    "the backup wrapper is not verbatim — first line that is absent: " +
                        section.lineSequence().firstOrNull { it !in script.contents } +
                        " (this side's text is in " +
                        "recipe/build/recipe-mismatch/${variant.name}__backup-ctl.sh)"
                }
            }
        }
    }

    @TestFactory
    fun `the update wrapper is in the Swift script verbatim`(): List<DynamicTest> {
        assertTrue(runs.isNotEmpty(), "no dumped variant grants dashboard access")
        return runs.map { (variant, _, script) ->
            DynamicTest.dynamicTest("${variant.name}/${script.fileName}") {
                val context = GoldenFixture.context(variant)
                val serviceContext = accessContext(variant)
                val services = context.allSelectedServices
                val section = UpdateControlSections.wrapper(
                    services = services, context = serviceContext, language = context.language
                )
                if (!UpdateControlSections.isUsed(services, serviceContext)) {
                    assertTrue("EOF_UPDATE_CTL" !in script.contents) {
                        "${script.fileName} writes the wrapper for a host with nothing to update"
                    }
                    return@dynamicTest
                }
                if (!script.contents.contains(section)) {
                    val out = java.io.File("build/recipe-mismatch")
                    out.mkdirs()
                    java.io.File(out, "${variant.name}__update-ctl.sh").writeText(section)
                }
                assertTrue(script.contents.contains(section)) {
                    "the update wrapper is not verbatim — first line that is absent: " +
                        section.lineSequence().firstOrNull { it !in script.contents } +
                        " (this side's text is in " +
                        "recipe/build/recipe-mismatch/${variant.name}__update-ctl.sh)"
                }
            }
        }
    }

    @TestFactory
    fun `the uninstall wrapper is in the Swift script verbatim`(): List<DynamicTest> =
        runs.map { (variant, access, script) ->
            DynamicTest.dynamicTest("${variant.name}/${script.fileName}") {
                val context = GoldenFixture.context(variant)
                val section = UninstallSections.servicesHostWrapper(
                    access = GoldenFixture.input(variant).dashboardAccess!!,
                    context = context,
                    includeWireGuard = variant.topology != "singleHost"
                )
                assertContained(section, script, variant.name, "uninstall")
            }
        } + GoldenFixture.samples.filter { it.fileName == "setup-vps.sh" }.mapNotNull { sample ->
            val variant = GoldenFixture.variants.firstOrNull { it.name == sample.variant }
                ?: return@mapNotNull null
            val access = GoldenFixture.input(variant).dashboardAccess ?: return@mapNotNull null
            DynamicTest.dynamicTest("${variant.name}/${sample.fileName}") {
                assertContained(UninstallSections.vpsWrapper(access, language(variant)),
                                sample, variant.name, "uninstall-vps")
            }
        }

    /** The whole dashboard-access section of each host, in one piece */
    @TestFactory
    fun `the dashboard access section is in the Swift script verbatim`(): List<DynamicTest> =
        runs.map { (variant, access, script) ->
            DynamicTest.dynamicTest("${variant.name}/${script.fileName}") {
                val context = GoldenFixture.context(variant)
                val section = if (variant.topology == "singleHost") {
                    DashboardAccessSections.singleHostSection(access = access, context = context)
                } else {
                    DashboardAccessSections.homeSection(access = access, context = context)
                }
                assertContained(section, script, variant.name, "dashboard-access")
            }
        } + GoldenFixture.samples.filter { it.fileName == "setup-vps.sh" }.mapNotNull { sample ->
            val variant = GoldenFixture.variants.firstOrNull { it.name == sample.variant }
                ?: return@mapNotNull null
            val access = GoldenFixture.input(variant).dashboardAccess ?: return@mapNotNull null
            DynamicTest.dynamicTest("${variant.name}/${sample.fileName}") {
                assertContained(DashboardAccessSections.vpsSection(access, language(variant)),
                                sample, variant.name, "dashboard-access-vps")
            }
        }

    @TestFactory
    fun `the install-key revocation is in every script that grants access`(): List<DynamicTest> =
        GoldenFixture.samples.filter { it.fileName.endsWith(".sh") }.mapNotNull { sample ->
            val variant = GoldenFixture.variants.firstOrNull { it.name == sample.variant }
                ?: return@mapNotNull null
            val access = GoldenFixture.input(variant).dashboardAccess ?: return@mapNotNull null
            DynamicTest.dynamicTest("${variant.name}/${sample.fileName}") {
                assertContained(DashboardAccessSections.revokeInstallKey(access, language(variant)),
                                sample, variant.name, "revoke-install-key")
            }
        }

    @TestFactory
    fun `the uninstall lines are in every script that grants access`(): List<DynamicTest> =
        GoldenFixture.samples.filter { it.fileName.endsWith(".sh") }.mapNotNull { sample ->
            val variant = GoldenFixture.variants.firstOrNull { it.name == sample.variant }
                ?: return@mapNotNull null
            if (variant.access == null) return@mapNotNull null
            DynamicTest.dynamicTest("${sample.variant}/${sample.fileName}") {
                for ((what, lines) in mapOf(
                    "backup" to ::backupUninstallLines, "update" to ::updateUninstallLines
                )) {
                    val nested = lines("  ")
                    val flat = lines("")
                    assertTrue(sample.contents.contains(nested) ||
                                   sample.contents.contains(flat)) {
                        "neither indent of the $what uninstall lines is in " +
                            "${sample.fileName} — first flat line that is absent: " +
                            flat.lineSequence().firstOrNull { it !in sample.contents }
                    }
                }
            }
        }

    private fun backupUninstallLines(indent: String): String =
        BackupControlSections.uninstallLines(indent).joinToString("\n")

    private fun updateUninstallLines(indent: String): String =
        UpdateControlSections.uninstallLines(indent).joinToString("\n")

    private fun assertContained(section: String, sample: GoldenFixture.Sample,
                                variant: String, name: String) {
        if (!sample.contents.contains(section)) {
            val out = java.io.File("build/recipe-mismatch")
            out.mkdirs()
            java.io.File(out, "${variant}__$name.sh").writeText(section)
        }
        assertTrue(sample.contents.contains(section)) {
            "the $name section is not verbatim — first line that is absent: " +
                section.lineSequence().firstOrNull { it !in sample.contents } +
                " (this side's text is in recipe/build/recipe-mismatch/${variant}__$name.sh)"
        }
    }

    private fun language(variant: GoldenFixture.GoldenVariant): AppLanguage =
        checkNotNull(AppLanguage.from(variant.language))
}
