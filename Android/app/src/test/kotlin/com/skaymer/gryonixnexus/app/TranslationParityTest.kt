package com.skaymer.gryonixnexus.app

import java.io.File
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.w3c.dom.Element
import javax.xml.parsers.DocumentBuilderFactory

class TranslationParityTest {
    private fun repoRoot(): File {
        val cwd = requireNotNull(System.getProperty("user.dir")) { "no working directory" }
        var here: File? = File(cwd).absoluteFile
        while (here != null && !File(here, "settings.gradle.kts").isFile) {
            here = here.parentFile
        }
        val android = requireNotNull(here) { "no settings.gradle.kts above the working directory" }
        return requireNotNull(android.parentFile) { "no repository above ${android.path}" }
    }

    private fun res() = File(repoRoot(), "Android/app/src/main/res")

    private val languages = listOf("de", "es", "fr", "it", "ja", "ru", "uk", "zh")

    /** name -> text, for the `<string>` elements of one values directory */
    private fun strings(directory: String): Map<String, String> {
        val file = File(res(), "$directory/strings.xml")
        assertTrue(file.isFile, "no strings.xml in $directory")
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val nodes = document.getElementsByTagName("string")
        val map = LinkedHashMap<String, String>()
        for (i in 0 until nodes.length) {
            val element = nodes.item(i) as Element
            map[element.getAttribute("name")] = element.textContent
        }
        return map
    }

    private fun arguments(text: String): Map<Int, String> {
        val pattern = Regex("""%(?:(\d+)\$)?(\.\d+f|[sdf])""")
        val found = LinkedHashMap<Int, String>()
        var next = 1
        for (match in pattern.findAll(text)) {
            val explicit = match.groupValues[1]
            val index = if (explicit.isNotEmpty()) explicit.toInt() else next++
            found.putIfAbsent(index, match.groupValues[2])
        }
        return found
    }

    @Test
    fun `every translation asks for exactly the arguments the English one does`() {
        val english = strings("values")
        for (language in languages) {
            for ((name, text) in strings("values-$language")) {
                val source = english[name] ?: continue
                assertEquals(
                    arguments(source), arguments(text),
                    "values-$language/$name asks for different arguments than the English " +
                        "string: \"$text\" against \"$source\" — a mismatch here is an " +
                        "IllegalFormatException the moment that screen is drawn",
                )
            }
        }
    }

    /** name -> quantity -> text, for the `<plurals>` of one values directory */
    private fun plurals(directory: String): Map<String, Map<String, String>> {
        val file = File(res(), "$directory/strings.xml")
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val nodes = document.getElementsByTagName("plurals")
        val map = LinkedHashMap<String, Map<String, String>>()
        for (i in 0 until nodes.length) {
            val element = nodes.item(i) as Element
            val items = element.getElementsByTagName("item")
            val quantities = LinkedHashMap<String, String>()
            for (j in 0 until items.length) {
                val item = items.item(j) as Element
                quantities[item.getAttribute("quantity")] = item.textContent
            }
            map[element.getAttribute("name")] = quantities
        }
        return map
    }

    @Test
    fun `each language carries the plural categories it actually uses`() {
        val required = mapOf(
            "de" to setOf("one", "other"),
            "es" to setOf("one", "other"),
            "fr" to setOf("one", "other"),
            "it" to setOf("one", "other"),
            "ja" to setOf("other"),
            "ru" to setOf("one", "few", "many", "other"),
            "uk" to setOf("one", "few", "many", "other"),
            "zh" to setOf("other"),
        )
        val english = plurals("values").keys
        assertTrue(english.isNotEmpty(), "the English file declares no plurals at all")
        for (language in languages) {
            val got = plurals("values-$language")
            assertEquals(
                english, got.keys,
                "values-$language does not declare the same plurals as the English file",
            )
            for ((name, quantities) in got) {
                assertEquals(
                    required.getValue(language), quantities.keys,
                    "values-$language/$name declares ${quantities.keys} where $language uses " +
                        "${required.getValue(language)} — a category the language never asks " +
                        "for is dead text, and a missing one falls back to \"other\" and says " +
                        "the wrong form",
                )
                for ((quantity, text) in quantities) {
                    assertEquals(
                        arguments(english.let { _ -> plurals("values")[name]!!["other"]!! }),
                        arguments(text),
                        "values-$language/$name/$quantity asks for different arguments " +
                            "than the English plural",
                    )
                }
            }
        }
    }

    @Test
    fun `no translation names a string that no longer exists`() {
        val english = strings("values").keys
        for (language in languages) {
            val orphans = strings("values-$language").keys - english
            assertTrue(
                orphans.isEmpty(),
                "values-$language names ${orphans.size} strings the English file does not have " +
                    "(${orphans.take(5)}) — Android will never ask for them, so they are a file " +
                    "that stays looking right after the English side moved",
            )
        }
    }

    @Test
    fun `the eight languages carry the same strings as each other`() {
        val sets = languages.associateWith { strings("values-$it").keys }
        val reference = sets.getValue(languages.first())
        assertTrue(reference.size > 400, "values-${languages.first()} is nearly empty")
        for ((language, keys) in sets) {
            assertEquals(
                emptySet<String>(), reference - keys,
                "values-$language is missing strings the other languages carry",
            )
            assertEquals(
                emptySet<String>(), keys - reference,
                "values-$language carries strings the other languages do not",
            )
        }
    }
}
