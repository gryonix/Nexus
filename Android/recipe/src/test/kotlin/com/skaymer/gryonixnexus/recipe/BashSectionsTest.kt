package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.core.DebianProfile
import com.skaymer.gryonixnexus.core.DistributionProfile
import com.skaymer.gryonixnexus.core.UbuntuProfile
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

class BashSectionsTest {
    private val samples: List<GoldenFixture.Sample> get() = GoldenFixture.samples

    private val headerEnd = "export DEBIAN_FRONTEND=noninteractive"

    private fun scripts(): List<GoldenFixture.Sample> = samples.filter { it.fileName.endsWith(".sh") }

    private fun profileFor(fileName: String): DistributionProfile =
        if (fileName == "setup-home-server.sh") UbuntuProfile() else DebianProfile()

    private fun languageFor(variant: String): AppLanguage =
        if (variant.endsWith("-ru")) AppLanguage.RU else AppLanguage.EN

    private fun purposeOf(script: String): String =
        script.lineSequence().first { it.startsWith("# Managed by gryonixNexus — ") }
            .removePrefix("# Managed by gryonixNexus — ")

    @TestFactory
    fun `the shared header matches the Swift text byte for byte`(): List<DynamicTest> {
        assertTrue(scripts().isNotEmpty(), "the fixture carries no setup scripts")
        return scripts().map { sample ->
            DynamicTest.dynamicTest("${sample.variant}/${sample.fileName}") {
                val want = sample.contents.substringBefore(headerEnd) + headerEnd
                val got = BashSections.header(
                    scriptName = sample.fileName,
                    purpose = purposeOf(sample.contents),
                    profile = profileFor(sample.fileName),
                    language = languageFor(sample.variant)
                )
                assertEquals(want, got, "${sample.fileName}: the shared header differs")
            }
        }
    }

    /** The firewall block, checked against every script that carries one */
    @TestFactory
    fun `the firewall block appears in the Swift text, edits included`(): List<DynamicTest> =
        scripts().mapNotNull { sample ->
            val marker = "cat > /etc/nftables.conf <<'EOF_NFT'\n"
            if (marker !in sample.contents) return@mapNotNull null
            DynamicTest.dynamicTest("${sample.variant}/${sample.fileName}") {
                val ruleset = sample.contents.substringAfter(marker).substringBefore("\nEOF_NFT")
                var block = BashSections.applyFirewall(ruleset)
                if (sample.fileName == "setup-vps.sh") {
                    block = block.replace(
                        "nft -c -f /etc/nftables.conf",
                        "sed -i \"s|${NftablesConfig.PUBLIC_INTERFACE_PLACEHOLDER}|${SH}PUB_IF|g\" " +
                            "/etc/nftables.conf\nnft -c -f /etc/nftables.conf"
                    )
                }
                assertTrue(sample.contents.contains(block)) {
                    "${sample.fileName}: this side's firewall block is not in the Swift script — " +
                        "first line that is absent: " +
                        block.lineSequence().firstOrNull { it !in sample.contents }
                }
            }
        }
}
