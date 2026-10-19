package com.skaymer.gryonixnexus.servercontrol

import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class TransferSealTest {
    /** Made with Python cryptography; Swift opens it too */
    private val vector = """{"ciphertext":"YtZyqfGCtfSalFk7MDRWgQKi1GAWtsOd5ERDwY9ESjtPo8sbaZ9tGg==","iterations":600000,"kdf":"pbkdf2-sha256","nonce":"ZGVmZ2hpamtsbW5v","salt":"AAECAwQFBgcICQoLDA0ODw==","type":"gryonixserver-sealed","version":1}"""

    @Test
    fun `an independently made file opens`() {
        val plain = TransferSeal.open(vector.toByteArray(), "correct horse battery")
        assertEquals("""{"hello":"Привет"}""", plain.decodeToString())
    }

    @Test
    fun `fixed inputs seal to the same bytes as Swift and Python`() {
        val sealed = TransferSeal.seal(
            """{"hello":"Привет"}""".toByteArray(), "correct horse battery",
            salt = ByteArray(16) { it.toByte() }, nonce = ByteArray(12) { (100 + it).toByte() },
        )
        assertEquals(vector, sealed.decodeToString())
    }

    @Test
    fun `the wrong passphrase is told apart from a broken file`() {
        val sealed = TransferSeal.seal("{}".toByteArray(), "right")
        assertTrue(TransferSeal.isSealed(sealed))
        assertFalse(TransferSeal.isSealed("{}".toByteArray()))
        assertContentEquals("{}".toByteArray(), TransferSeal.open(sealed, "right"))
        assertFailsWith<TransferSeal.WrongPassphrase> { TransferSeal.open(sealed, "wrong") }
        assertFailsWith<TransferSeal.Unreadable> { TransferSeal.open("{}".toByteArray(), "right") }
    }
}
