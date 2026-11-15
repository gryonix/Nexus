package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.servercontrol.SshKeyKind
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class UserSshKeyGeneratorTest {
    @Test
    fun generatedKeysHaveExpectedFormats() {
        for (kind in listOf(SshKeyKind.ED25519, SshKeyKind.ECDSA_P256, SshKeyKind.RSA_3072)) {
            val key = UserSshKeyGenerator.generate(kind, "k")
            assertTrue(key.publicKey.startsWith(kind.algorithm + " AAAA"))
            assertTrue(key.fingerprint.startsWith("SHA256:"))
            assertTrue(key.privateKeyPem.startsWith("-----BEGIN OPENSSH PRIVATE KEY-----\n"))
            assertEquals(11, key.randomArt.lines().size)
        }
    }

    @Test
    fun sshKeygenAcceptsGeneratedKeysWhenInstalled() {
        val tool = File("/usr/bin/ssh-keygen")
        if (!tool.exists()) return
        for (kind in listOf(SshKeyKind.ED25519, SshKeyKind.ECDSA_P256, SshKeyKind.RSA_3072)) {
            val key = UserSshKeyGenerator.generate(kind, "k")
            val file = kotlin.io.path.createTempFile().toFile()
            file.writeText(key.privateKeyPem)
            val process = ProcessBuilder(tool.path, "-y", "-f", file.path).start()
            val printed = process.inputStream.readBytes().decodeToString()
            assertEquals(0, process.waitFor(), kind.name)
            assertTrue(printed.startsWith(key.publicKey.split(" ").take(2).joinToString(" ")), kind.name)
            file.delete()
        }
    }
}
