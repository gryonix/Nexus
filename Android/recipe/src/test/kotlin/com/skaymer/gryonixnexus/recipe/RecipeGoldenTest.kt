package com.skaymer.gryonixnexus.recipe

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.security.MessageDigest

class RecipeGoldenTest {
    private val golden: List<GoldenFixture.GoldenVariant> get() = GoldenFixture.variants

    private val fixedKeys = WireGuardKeyProvider {
        WireGuardKeyPair(privateKey = "TEST-PRIVATE-KEY=", publicKey = "TEST-PUBLIC-KEY=")
    }

    private fun sha256(text: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(text.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    @TestFactory
    fun `every generated artifact matches the Swift bytes`(): List<DynamicTest> {
        assertTrue(golden.isNotEmpty(), "the golden is empty")
        return golden.map { variant ->
            DynamicTest.dynamicTest(variant.name) {
                val produced = MailRecipe(fixedKeys).generate(GoldenFixture.input(variant))
                val expected = variant.artifacts.associateBy { it.fileName }
                for (artifact in produced.artifacts) {
                    val want = requireNotNull(expected[artifact.fileName]) {
                        "${variant.name}: this side generated ${artifact.fileName}, " +
                            "which the Swift run does not produce at all"
                    }
                    if (want.sha256 != sha256(artifact.contents)) {
                        val out = java.io.File("build/recipe-mismatch")
                        out.mkdirs()
                        java.io.File(out, "${variant.name}__${artifact.fileName}")
                            .writeText(artifact.contents)
                    }
                    assertEquals(want.bytes, artifact.contents.toByteArray(Charsets.UTF_8).size,
                                 "${artifact.fileName}: length")
                    assertEquals(want.sha256, sha256(artifact.contents),
                                 "${artifact.fileName}: contents differ — this side's text is in " +
                                     "recipe/build/recipe-mismatch/${variant.name}__${artifact.fileName}")
                }
            }
        }
    }

    @TestFactory
    fun `the bundle carries the same files, warnings and notes`(): List<DynamicTest> =
        golden.map { variant ->
            DynamicTest.dynamicTest(variant.name) {
                val produced = MailRecipe(fixedKeys).generate(GoldenFixture.input(variant))
                assertEquals(variant.artifacts.map { it.fileName },
                             produced.artifacts.map { it.fileName },
                             "${variant.name}: the artifact list differs from the Swift run")
                assertEquals(variant.warnings, produced.warnings, "${variant.name}: warnings")
                assertEquals(variant.notes, produced.notes, "${variant.name}: notes")
            }
        }

    @TestFactory
    fun `every service script matches the Swift bytes`(): List<DynamicTest> =
        golden.map { variant ->
            DynamicTest.dynamicTest(variant.name) {
                val produced = MailRecipe(fixedKeys).generate(GoldenFixture.input(variant)).serviceScripts
                assertEquals(variant.serviceScripts.map { it.fileName }, produced.map { it.fileName },
                             "${variant.name}: the service scripts differ from the Swift run")
                variant.serviceScripts.zip(produced).forEach { (want, artifact) ->
                    if (want.sha256 != sha256(artifact.contents)) {
                        java.io.File("build/recipe-mismatch").mkdirs()
                        java.io.File("build/recipe-mismatch/${variant.name}__${artifact.fileName}")
                            .writeText(artifact.contents)
                    }
                    assertEquals(want.sha256, sha256(artifact.contents),
                                 "${artifact.fileName}: contents differ — see recipe/build/recipe-mismatch")
                }
            }
        }
}
