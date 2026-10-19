package com.skaymer.gryonixnexus.agentclient

import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.junit.jupiter.api.Test

class PairingCodeTest {
    @Test
    fun `the real CLI banner yields only the code`() {
        assertEquals("AKAD-M3RJ", PairingCode.parse("Pairing code (valid 10 minutes): AKAD-M3RJ\n"))
    }

    @Test
    fun `a bare code parses`() {
        assertEquals("AKAD-M3RJ", PairingCode.parse("AKAD-M3RJ"))
    }

    @Test
    fun `earlier log lines are ignored`() {
        val output = "starting up\nsome log line\nPairing code (valid 10 minutes): 7Q9M-KZ2P\n"
        assertEquals("7Q9M-KZ2P", PairingCode.parse(output))
    }

    @Test
    fun `nothing to parse is null, not an empty code`() {
        assertNull(PairingCode.parse(""))
        assertNull(PairingCode.parse("\n   \n"))
    }
}
