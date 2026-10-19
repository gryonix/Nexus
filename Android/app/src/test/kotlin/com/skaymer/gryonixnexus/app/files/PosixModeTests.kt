package com.skaymer.gryonixnexus.app.files

import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.junit.jupiter.api.Test

/** The permission columns, as `ls -l` writes them */
class PosixModeTests {
    @Test
    fun `the type character comes from the same bits the kind does`() {
        // 0o040755 — a directory anybody may walk into.
        assertEquals("drwxr-xr-x", PosixMode.format(0x41ED))
        // 0o100600 — the mode the agent writes an .env with.
        assertEquals("-rw-------", PosixMode.format(0x8180))
        assertEquals("lrwxrwxrwx", PosixMode.format(0xA1FF))
    }

    @Test
    fun `a type this app does not know says so instead of guessing`() {
        assertEquals("?rw-rw----", PosixMode.format(0x61B0))
    }

    @Test
    fun `a listing that carried no mode word states nothing`() {
        assertNull(PosixMode.format(null))
    }

    @Test
    fun `setuid and the sticky bit are the columns they take over`() {
        assertEquals("-rwsr-xr-x", PosixMode.format(0x89ED))
        assertEquals("-rwSr--r--", PosixMode.format(0x89A4))
        // 0o041777 — /tmp: sticky and executable by all.
        assertEquals("drwxrwxrwt", PosixMode.format(0x43FF))
    }
}
