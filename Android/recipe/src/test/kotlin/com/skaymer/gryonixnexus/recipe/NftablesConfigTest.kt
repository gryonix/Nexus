package com.skaymer.gryonixnexus.recipe

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory

class NftablesConfigTest {
    private val samples: List<GoldenFixture.Sample> get() = GoldenFixture.samples

    private fun context(variantName: String): MailContext =
        GoldenFixture.context(
            requireNotNull(GoldenFixture.variants.firstOrNull { it.name == variantName }) {
                "$variantName is not in the golden"
            }
        )

    @TestFactory
    fun `each ruleset matches the one in the Swift script`(): List<DynamicTest> {
        val scripts = samples.filter { it.fileName.endsWith(".sh") }
        assertTrue(scripts.isNotEmpty(), "the fixture carries no setup scripts")
        return scripts.map { sample ->
            DynamicTest.dynamicTest("${sample.variant}/${sample.fileName}") {
                val want = sample.contents
                    .substringAfter("cat > /etc/nftables.conf <<'EOF_NFT'\n")
                    .substringBefore("\nEOF_NFT")
                val context = context(sample.variant)
                val got = when (sample.fileName) {
                    "setup-mail-server.sh" -> NftablesConfig.singleHostRuleset(context)
                    "setup-home-server.sh" -> NftablesConfig.homeRuleset(context)
                    "setup-vps.sh" -> checkNotNull(NftablesConfig.vpsRuleset(context)) {
                        "the relay ruleset came back null for a scenario-B pair"
                    }
                    else -> error("unexpected script ${sample.fileName}")
                }
                assertEquals(want, got, "${sample.fileName}: the ruleset differs")
            }
        }
    }

    @TestFactory
    fun `each sysctl file matches the Swift text`(): List<DynamicTest> =
        samples.filter { it.fileName.endsWith(".sh") }.mapNotNull { sample ->
            val marker = "<<'EOF_SYSCTL'\n"
            if (marker !in sample.contents) return@mapNotNull null
            DynamicTest.dynamicTest("${sample.variant}/${sample.fileName}") {
                val want = sample.contents.substringAfter(marker).substringBefore("\nEOF_SYSCTL")
                val got = if (sample.fileName == "setup-vps.sh") NftablesConfig.vpsSysctl
                          else NftablesConfig.homeSysctl
                assertEquals(want, got, "${sample.fileName}: the sysctl file differs")
            }
        }
}
