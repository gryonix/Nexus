package com.skaymer.gryonixnexus.app.terminal

import org.junit.jupiter.api.Test
import kotlin.test.assertContentEquals

class TerminalKeysTests {
    @Test
    fun heldControlTurnsLettersIntoControlBytes() {
        assertContentEquals(byteArrayOf(0x01), TerminalKeys.typed("a", control = true))
        assertContentEquals(byteArrayOf(0x1A, 0x03), TerminalKeys.typed("zC", control = true))
    }

    @Test
    fun heldControlLeavesOtherCharactersAlone() {
        assertContentEquals("1".toByteArray(), TerminalKeys.typed("1", control = true))
    }

    @Test
    fun withoutControlTextIsSentAsTyped() {
        assertContentEquals("ls".toByteArray(), TerminalKeys.typed("ls", control = false))
    }
}
