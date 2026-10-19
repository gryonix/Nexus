package com.skaymer.gryonixnexus.app.ui

import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class ThirdPartyNoticesTests {
    private val text = File("src/main/assets/${ThirdPartyNotices.ASSET}").readText()

    @Test
    fun `the notices name the cores the VPN links`() {
        for (name in listOf("xray-core", "amneziawg-android", "hev-socks5-tunnel", "androidx.core:core ")) {
            assertTrue(text.contains(name), "$name is missing from the notices")
        }
    }

    @Test
    fun `each block keeps its heading and its text together`() {
        val sample = "Title\n\nIntro\n" + RULE + "\nlib 1.0\n" + RULE + "\nMIT text\n\n" + RULE + "\nlib2 2.0\n" + RULE + "\nBSD text\n"
        assertEquals(
            listOf("Title\n\nIntro", "lib 1.0\n\nMIT text", "lib2 2.0\n\nBSD text"),
            ThirdPartyNotices.split(sample),
        )
    }

    @Test
    fun `the real file splits into one block per component`() {
        val blocks = ThirdPartyNotices.split(text)
        assertTrue(blocks.size > 100, "only ${blocks.size} blocks")
        assertTrue(blocks.drop(1).none { it.startsWith("=") }, "a rule leaked into a block")
    }

    private companion object {
        const val RULE = "========================================================================"
    }
}
