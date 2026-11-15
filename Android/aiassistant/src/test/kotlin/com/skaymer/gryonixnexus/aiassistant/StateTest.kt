package com.skaymer.gryonixnexus.aiassistant

import java.io.File
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class StateTest {
    private val day = 86_400_000L
    private val now = 1_793_000_000_000L

    @Test fun ledgerPerMonth() {
        val ledger = AITokenLedger()
        ledger.add(100, now)
        ledger.add(50, now)
        ledger.add(-5, now)
        ledger.add(7, now + 40 * day)
        assertEquals(150, ledger.used(now))
        assertEquals(7, ledger.used(now + 40 * day))
    }

    @Test fun budgetStates() {
        assertEquals(AIBudgetState.UNLIMITED, AITokenLedger.state(999, 0))
        assertEquals(AIBudgetState.OK, AITokenLedger.state(79, 100))
        assertEquals(AIBudgetState.NEAR_LIMIT, AITokenLedger.state(80, 100))
        assertEquals(AIBudgetState.REACHED, AITokenLedger.state(100, 100))
    }

    @Test fun historyGroupsAndRoundTrip() {
        var history = AIChatHistory()
        for ((title, days) in listOf("a" to 0L, "b" to 1L, "c" to 3L, "d" to 30L)) {
            history = history.upsert(AIChat(title = title, updatedAt = now - days * day))
        }
        assertEquals(
            listOf(AIDateGroup.TODAY, AIDateGroup.YESTERDAY, AIDateGroup.LAST_WEEK, AIDateGroup.EARLIER),
            history.groups(now, ZoneOffset.UTC).map { it.first },
        )
        val file = File.createTempFile("chats", ".json")
        val store = AIChatFileStore(file)
        store.save(history)
        assertEquals(history, store.load())
        file.delete()
    }

    @Test fun upsertReplacesAndDelete() {
        val chat = AIChat(title = "x", updatedAt = now)
        var history = AIChatHistory().upsert(chat).upsert(chat.copy(title = "y"))
        assertEquals(1, history.chats.size)
        assertEquals("y", history.chats[0].title)
        history = history.delete(chat.id)
        assertTrue(history.chats.isEmpty())
    }

    @Test fun missingFileLoadsEmpty() {
        assertTrue(AIChatFileStore(File("/nonexistent/none.json")).load().chats.isEmpty())
    }

    @Test fun promptRedactsAndNeverClaimsAction() {
        val context = AIContext(AIContextKind.SERVICE, "web", listOf(AIContextSection("Logs", "ok\nPASSWORD=abc123\nend")))
        val text = AIPrompts.contextMessage(context)
        assertFalse(text.contains("abc123"))
        assertTrue(text.contains("### Logs"))
        val system = AIPrompts.systemPrompt("German")
        assertTrue(system.contains("cannot run commands"))
        assertTrue(system.contains("German"))
    }

    @Test fun promptKeepsTail() {
        val long = "x ".repeat(5000) + "LASTLINE"
        val text = AIPrompts.contextMessage(AIContext(AIContextKind.OPERATION, "t", listOf(AIContextSection("Log", long))))
        assertTrue(text.contains("LASTLINE"))
        assertTrue(text.length < 7000)
    }

    @Test fun markdown() {
        assertEquals(
            listOf(
                MarkdownBlock.Heading(1, "T"), MarkdownBlock.Paragraph("hello"),
                MarkdownBlock.Bullets(listOf("a", "b")), MarkdownBlock.Code("sh", "ls -l"),
                MarkdownBlock.Numbered(listOf("x", "y")),
            ),
            MarkdownBlocks.parse("# T\nhello\n\n- a\n- b\n\n```sh\nls -l\n```\n1. x\n2. y"),
        )
    }

    @Test fun markdownOpenFence() {
        assertEquals(listOf(MarkdownBlock.Code("", "ls")), MarkdownBlocks.parse("```\nls"))
    }

    @Test fun ramTable() {
        assertEquals(4, OllamaRam.requiredGb("llama3.2:3b"))
        assertEquals(8, OllamaRam.requiredGb("qwen2.5:7b"))
        assertEquals(8, OllamaRam.requiredGb("llama3.1:8b-instruct-q4"))
        assertEquals(16, OllamaRam.requiredGb("qwen2.5:14b"))
        assertEquals(32, OllamaRam.requiredGb("qwen2.5:32b"))
        assertEquals(32, OllamaRam.requiredGb("mixtral:8x7b"))
        assertNull(OllamaRam.requiredGb("phi3:mini"))
    }

    @Test fun ramVerdict() {
        val gb = 1_073_741_824L
        assertEquals(RamVerdict.TooLow(16, 8), OllamaRam.verdict("qwen2.5:14b", 8 * gb))
        assertEquals(RamVerdict.Enough, OllamaRam.verdict("qwen2.5:7b", 8 * gb))
        assertEquals(RamVerdict.Unknown, OllamaRam.verdict("qwen2.5:7b", null))
    }

    @Test fun weeklyDigest() {
        val text = AIWeeklyDigest.lines(
            "orion",
            listOf(AIUsageSample(0, 10.0, 0.5, 0.6, null), AIUsageSample(1, 30.0, 0.7, 0.7, 60.0)),
        )
        assertTrue(text.contains("CPU avg 20% max 30%"))
        assertTrue(text.contains("disk 60% -> 70%"))
        assertTrue(AIWeeklyDigest.lines("x", emptyList()).contains("no history"))
    }
}
