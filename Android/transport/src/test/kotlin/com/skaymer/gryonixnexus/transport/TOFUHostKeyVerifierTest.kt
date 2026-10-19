package com.skaymer.gryonixnexus.transport

import com.skaymer.gryonixnexus.servercontrol.OpenSSHPublicKey
import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import java.security.KeyPairGenerator
import java.security.PublicKey
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class TOFUHostKeyVerifierTest {
    private fun hostKey(): PublicKey =
        KeyPairGenerator.getInstance("Ed25519").generateKeyPair().public

    private val inline = Executor { it.run() }

    // ----------------------------------------------------------- First use

    @Test
    fun `the first connection trusts the key and reports it for pinning`() {
        val key = hostKey()
        val pinned = AtomicReference<String?>(null)
        val verifier = TOFUHostKeyVerifier("vps", pinnedKey = null, reporter = inline) {
            pinned.set(it)
        }

        assertTrue(verifier.verify("example.com", 22, key))
        assertEquals(TOFUHostKeyVerifier.openSSHString(key), pinned.get())
    }

    // --------------------------------------------------------- Later uses

    @Test
    fun `a matching key is accepted and nothing is reported again`() {
        val key = hostKey()
        val reported = AtomicReference<String?>(null)
        val verifier = TOFUHostKeyVerifier(
            "vps",
            pinnedKey = TOFUHostKeyVerifier.openSSHString(key),
            reporter = inline,
        ) { reported.set(it) }

        assertTrue(verifier.verify("example.com", 22, key))
        assertNull(reported.get(), "a key that was already pinned must not be re-reported")
    }

    @Test
    fun `a different key is refused with the mismatch this project names`() {
        val verifier = TOFUHostKeyVerifier(
            "vps-middle",
            pinnedKey = TOFUHostKeyVerifier.openSSHString(hostKey()),
            reporter = inline,
        ) { }

        val error = assertFailsWith<ServerControlError.HostKeyMismatch> {
            verifier.verify("example.com", 22, hostKey())
        }
        assertEquals("vps-middle", error.host)
        assertTrue(error.message.orEmpty().contains("vps-middle"), error.message.orEmpty())
    }

    // ------------------------------------------------------- The encoding

    @Test
    fun `sshj spells a host key the way this project's own encoder does`() {
        val key = hostKey()
        // X.509 SubjectPublicKeyInfo for Ed25519 ends with the 32 raw bytes.
        val raw = key.encoded.copyOfRange(key.encoded.size - 32, key.encoded.size)

        val ours = OpenSSHPublicKey.encode(raw, comment = "")
        val theirs = TOFUHostKeyVerifier.openSSHString(key)

        // Ours carries a trailing comment field; the host-key form has none.
        assertEquals(ours.trim(), theirs)
        assertTrue(theirs.startsWith("ssh-ed25519 "), theirs)
    }

    // -------------------------------------------------- The handshake thread

    /**
     * The measured hazard: sshj calls `verify` on the connection's own thread
     * during key exchange, and the pin write goes to the platform keystore,
     * which blocks. Whatever it waits for, an UNAUTHENTICATED handshake waits
     * for with it — and past LoginGraceTime that is a per-source penalty on
     * OpenSSH 9.8+, i.e. this client refused for 15 s minimum.
     *
     * So the claim is not "it reports the pin" but "it does not report it HERE".
     * The reporter blocks for as long as the test likes; `verify` must return
     * anyway.
     */
    @Test
    fun `a slow pin write does not hold up the handshake`() {
        val released = CountDownLatch(1)
        val started = CountDownLatch(1)
        val verifier = TOFUHostKeyVerifier("vps", pinnedKey = null) {
            started.countDown()
            released.await(10, TimeUnit.SECONDS)
        }

        val handshake = CompletableFuture.supplyAsync { verifier.verify("example.com", 22, hostKey()) }
        try {
            assertTrue(handshake.get(2, TimeUnit.SECONDS), "the key should have been trusted")
        } finally {
            released.countDown()
        }

        assertTrue(started.await(5, TimeUnit.SECONDS), "the pin was never reported at all")
    }

    @Test
    fun `an inline reporter really would block, which is what the default avoids`() {
        val verifier = TOFUHostKeyVerifier("vps", pinnedKey = null, reporter = inline) {
            Thread.sleep(120)
        }

        val started = System.nanoTime()
        verifier.verify("example.com", 22, hostKey())
        val elapsedMillis = (System.nanoTime() - started) / 1_000_000

        assertTrue(elapsedMillis >= 100, "the inline reporter did not block: ${elapsedMillis}ms")
    }

    @Test
    fun `no algorithm is claimed as already known`() {
        val verifier = TOFUHostKeyVerifier("vps", pinnedKey = null, reporter = inline) { }
        assertEquals(emptyList(), verifier.findExistingAlgorithms("example.com", 22))
        assertNotNull(verifier)
    }
}
