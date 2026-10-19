package com.skaymer.gryonixnexus.servercontrol

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class MailboxListParserTest {
    @Test
    fun `a bulleted row becomes a mailbox with its quota text kept verbatim`() {
        val output = """
            * user@example.com ( 0 / ~ ) [0%]
            * second@example.com ( 1024 / 5120 ) [20%]
        """.trimIndent()
        val mailboxes = MailboxListParser.parse(output)
        assertEquals(listOf("user@example.com", "second@example.com"), mailboxes.map { it.address })
        assertEquals("( 0 / ~ ) [0%]", mailboxes[0].detail)
        assertEquals("user", mailboxes[0].localPart)
        assertEquals("example.com", mailboxes[0].domain)
    }

    @Test
    fun `a bare address with no quota text is still a mailbox`() {
        val mailboxes = MailboxListParser.parse("user@example.com")
        assertEquals(1, mailboxes.size)
        assertNull(mailboxes[0].detail)
    }

    /** The line that cost this parser its first shape */
    @Test
    fun `prose that mentions an address is not a mailbox`() {
        val output = """
            WARN  no accounts yet
            doveadm(user@example.com): Error: User doesn't exist
            Error: other@example.com not found
            no such thing as an @ here
        """.trimIndent()
        assertEquals(emptyList(), MailboxListParser.parse(output))
    }

    @Test
    fun `the same address listed twice is one mailbox`() {
        val output = "* user@example.com ( 0 / ~ )\n* user@example.com ( 0 / ~ )"
        assertEquals(1, MailboxListParser.parse(output).size)
    }

    @Test
    fun `manageability is a separate question from being listed`() {
        assertTrue(Mailbox("user@example.com").isManageable)
        assertFalse(Mailbox("пользователь@example.com").isManageable)
    }
}
