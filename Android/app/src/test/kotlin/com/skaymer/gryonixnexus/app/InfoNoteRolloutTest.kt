package com.skaymer.gryonixnexus.app

import java.io.File
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class InfoNoteRolloutTest {
    private fun appSources(): File {
        var here = File(System.getProperty("user.dir")).absoluteFile
        while (here.parentFile != null && !File(here, "settings.gradle.kts").isFile) {
            here = here.parentFile
        }
        return File(here, "app/src/main/kotlin")
    }

    private fun sources(): List<File> =
        appSources().walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()

    private val statedInline = setOf(
        "VPNSection.kt",
    )

    /** `GroupedSection(` … `)` up to the content lambda */
    private fun sectionHeads(text: String): List<Pair<Int, String>> {
        val heads = mutableListOf<Pair<Int, String>>()
        Regex("\\bGroupedSection\\(").findAll(text).forEach { match ->
            val tail = text.substring(match.range.last + 1)
            val head = tail.substringBefore('{')
            val line = text.take(match.range.first).count { it == '\n' } + 1
            heads += line to head
        }
        return heads
    }

    @Test
    fun `a headed section does not print a fixed explainer under its plate`() {
        val fixedExplainer = Regex("footer\\s*=\\s*stringResource\\(R\\.string\\.\\w*(_hint|_footer)\\)(?!\\s*\\.)")
        val offenders = mutableListOf<String>()
        var scanned = 0

        for (file in sources()) {
            scanned++
            if (file.name in statedInline) continue
            val text = file.readText()
            for ((line, head) in sectionHeads(text)) {
                if (!head.contains("header")) continue
                val hit = fixedExplainer.find(head) ?: continue
                offenders += "${file.name}:$line  ${hit.value}"
            }
        }

        assertTrue(scanned > 100, "the source sweep found almost nothing ($scanned files) — check the path")
        assertEquals(
            emptyList<String>(), offenders,
            """
            These print a steady explanation as a grey paragraph. Pass it as `note =`
            instead: GroupedSection renders the heading with an "i" and puts the text in
            the sheet behind it. If the sentence is really about the current STATE — a
            failure, a limit, something to act on — it belongs inline; name the file in
            statedInline and say why.
            ${offenders.joinToString("\n")}
            """.trimIndent(),
        )
    }

    @Test
    fun `no note is built out of an error`() {
        val offenders = mutableListOf<String>()

        for (file in sources()) {
            val text = file.readText()
            for ((line, head) in sectionHeads(text)) {
                val note = Regex("note\\s*=\\s*(.+?)(?:,\\s*\\n|\\n\\s*\\))", RegexOption.DOT_MATCHES_ALL)
                    .find(head)?.groupValues?.get(1) ?: continue
                if (Regex("[Ee]rror|[Ff]ailure|errorMessage").containsMatchIn(note)) {
                    offenders += "${file.name}:$line  ${note.trim().take(80)}"
                }
            }
        }

        assertEquals(
            emptyList<String>(), offenders,
            """
            A note is only opened when somebody taps the "i", so a failure put there is a
            failure nobody is told about. Keep the error in `footer =`, inline under the
            plate, and leave the note for what the section always means:
            ${offenders.joinToString("\n")}
            """.trimIndent(),
        )
    }

    @Test
    fun `the notes are in use across the app`() {
        val withNotes = sources().filter { file ->
            sectionHeads(file.readText()).any { (_, head) -> head.contains("note") }
        }

        assertTrue(
            withNotes.size >= 10,
            "only ${withNotes.size} screens pass a note — the rollout is the point of the rule",
        )
    }
}
