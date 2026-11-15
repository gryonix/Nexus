package com.skaymer.gryonixnexus.servercontrol

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SshKeysTest {
    private val ed25519 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAUMolS1zrD6Ge2IVa266sEAEprkKRu0lYVShpHUWitM test"
    private val ecdsa = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBBVDeILoz30CLxOBTtE7dmpT0qonP/29dri6/7C41teLkvEwzkyHCY6+0f9jyDjOWlEcSrKCgMdK1EnBkNiySZ0= test"

    @Test
    fun ed25519FingerprintAndRandomartMatchOpenSsh() {
        assertEquals("SHA256:luP6EoiNAAte1PsxDv5/E4CNh1YSAK3Dw5d/Lq76cx4", SshFingerprint.sha256(ed25519))
        val expected = listOf(
            "+--[ED25519 256]--+",
            "|  .o+....        |",
            "|o  . o . .       |",
            "|+.+ . o B        |",
            "|o. * = B =       |",
            "| . +=.* S .      |",
            "|  o o..* o .     |",
            "|      .E+   .    |",
            "|     ..=.. o     |",
            "|   .ooB=+.. .    |",
            "+----[SHA256]-----+",
        ).joinToString("\n")
        assertEquals(expected, SshFingerprint.randomArt(ed25519, SshKeyKind.ED25519))
    }

    @Test
    fun ecdsaFingerprintAndRandomartMatchOpenSsh() {
        assertEquals("SHA256:SNpaWEgF6TTeTiziByRxba56EDD+lZYKt+W0uo53RD0", SshFingerprint.sha256(ecdsa))
        val art = SshFingerprint.randomArt(ecdsa, SshKeyKind.ECDSA_P256)!!.lines()
        assertEquals("+---[ECDSA 256]---+", art.first())
        assertEquals("|.oo.=#+E         |", art[4])
    }

    @Test
    fun commandRejectsUnsafeLines() {
        assertNotNull(AuthorizedKeysInstall.command(ed25519))
        assertNull(AuthorizedKeysInstall.command("ssh-ed25519 x'; rm -rf / #"))
        assertNull(AuthorizedKeysInstall.command("junk"))
    }

    @Test
    fun commandIsIdempotentAndKeepsMode() {
        val home = kotlin.io.path.createTempDirectory("home").toFile()
        val command = AuthorizedKeysInstall.command(ed25519)!!
        fun run(): String {
            val builder = ProcessBuilder("/bin/sh", "-c", command)
            builder.environment().clear()
            builder.environment()["HOME"] = home.path
            builder.environment()["PATH"] = "/usr/bin:/bin"
            val process = builder.start()
            val out = process.inputStream.readBytes().decodeToString()
            process.waitFor()
            return out
        }
        assertTrue(AuthorizedKeysInstall.ADDED in run())
        assertTrue(AuthorizedKeysInstall.ALREADY_THERE in run())
        val file = File(home, ".ssh/authorized_keys")
        assertEquals(1, file.readLines().size)
        assertTrue(java.nio.file.Files.getPosixFilePermissions(file.toPath()).size == 2)
        home.deleteRecursively()
    }

    @Test
    fun outcomeParsing() {
        assertEquals(
            AuthorizedKeysInstall.Outcome.ADDED,
            AuthorizedKeysInstall.outcome(ExecResult(0, "gryonix-key-added\n", "")),
        )
        assertEquals(AuthorizedKeysInstall.Outcome.FAILED, AuthorizedKeysInstall.outcome(ExecResult(1, "", "x")))
    }
}
