package com.skaymer.gryonixnexus.recipe

import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.publishedHostPorts
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestFactory

class PortPreflightTest {
    private fun preflightScript(variant: String): GoldenFixture.Sample? =
        GoldenFixture.samples.singleOrNull {
            it.variant == variant && it.fileName.endsWith(".sh") && MARKER in it.contents
        }

    private val variantsWithSamples =
        GoldenFixture.variants.filter { v -> GoldenFixture.samples.any { it.variant == v.name } }

    @TestFactory
    fun `the pre-flight section matches the Swift text`(): List<DynamicTest> {
        assertTrue(variantsWithSamples.isNotEmpty(), "no dumped variant has a full text")
        return variantsWithSamples.map { variant ->
            DynamicTest.dynamicTest(variant.name) {
                val section = PortPreflightSections.section(GoldenFixture.context(variant))
                val script = preflightScript(variant.name)
                if (script == null) {
                    assertEquals(null, section,
                                 "${variant.name}: the Swift run has no pre-flight, this side built one")
                    return@dynamicTest
                }
                val block = checkNotNull(section) {
                    "${variant.name}: ${script.fileName} carries a pre-flight, this side built none"
                }
                assertTrue(script.contents.contains(block)) {
                    "${variant.name}/${script.fileName}: the pre-flight is not verbatim — " +
                        "first line that is absent: " +
                        block.lineSequence().firstOrNull { it !in script.contents }
                }
            }
        }
    }

    /** The argument the verification is called with, per service */
    @TestFactory
    fun `each service is verified with the mappings the Swift script names`(): List<DynamicTest> {
        val calls = variantsWithSamples.flatMap { variant ->
            val script = preflightScript(variant.name) ?: return@flatMap emptyList()
            CALL.findAll(script.contents)
                .map { Triple(variant, it.groupValues[1], it.groupValues[2]) }.toList()
        }
        assertTrue(calls.isNotEmpty(), "no dumped script calls the verification at all")
        return calls.map { (variant, wantedPorts, displayName) ->
            DynamicTest.dynamicTest("${variant.name}/$displayName") {
                val context = GoldenFixture.context(variant)
                val service = checkNotNull(
                    context.allSelectedServices.firstOrNull { it.displayName == displayName }
                ) { "the Swift script verifies «$displayName», which this side does not select" }
                assertEquals(wantedPorts, PortPreflightSections.verifyArgument(service, context))
            }
        }
    }

    @Test
    fun `the table carries loopback publishes and not only the public ports`() {
        val variant = GoldenFixture.variants.single { it.name == "A-homepage-full-noaccess-en" }
        val wanted = PortPreflightSections.wanted(GoldenFixture.context(variant))
        val adguard = wanted.filter { it.project == "adguardhome" }
            .map { "${it.port.address}:${it.port.label}" }
        assertEquals(listOf("127.0.0.1:8087/tcp", "127.0.0.1:53/tcp", "127.0.0.1:53/udp"), adguard)
    }

    @Test
    fun `every catalog port entry is understood`() {
        val variant = GoldenFixture.variants.single { it.name == "A-homepage-full-noaccess-en" }
        val context = MailContext(
            GoldenFixture.input(variant).copy(services = ServiceRegistry.all.map { it.id }.toSet())
        )
        var sawAny = false
        for (service in ServiceRegistry.all) {
            val compose = service.composeFile(context.serviceContext) ?: continue
            val byShape = compose.composeContents.split("\n").count { line ->
                val trimmed = line.trim(' ', '\t')
                if (!trimmed.startsWith("- ")) return@count false
                val entry = trimmed.drop(2).trim('"', '\'')
                val body = entry.substringBefore('/')
                val fields = body.split(":")
                when (fields.size) {
                    2 -> fields.all { it.toIntOrNull() in 0..65535 }
                    3 -> fields[0].split(".").size == 4 &&
                        fields.drop(1).all { it.toIntOrNull() in 0..65535 }
                    else -> false
                }
            }
            assertEquals(byShape, service.publishedHostPorts(context.serviceContext).size,
                         "${service.displayName}: the pre-flight does not read all of its published ports")
            sawAny = sawAny || byShape > 0
        }
        assertTrue(sawAny, "the fixture stopped producing compose bodies with ports at all")
    }

    @Test
    fun `every compose service brings itself up in one step`() {
        val variant = GoldenFixture.variants.single { it.name == "A-homepage-full-noaccess-en" }
        val context = MailContext(
            GoldenFixture.input(variant).copy(services = ServiceRegistry.all.map { it.id }.toSet())
        )
        for (service in ServiceRegistry.all) {
            if (service.composeFile(context.serviceContext) == null) continue
            assertTrue(service.setupSteps(context.serviceContext).any { "up -d" in it }) {
                "${service.displayName} has no step that brings its containers up"
            }
        }
    }

    private companion object {
        const val MARKER = "EOF_GD_PORTS"

        /** `gd_pp_verify <project> "<mappings>" "<display name>"` */
        val CALL = Regex("""^gd_pp_verify \S+ "([^"]*)" "([^"]*)"$""", RegexOption.MULTILINE)
    }
}
