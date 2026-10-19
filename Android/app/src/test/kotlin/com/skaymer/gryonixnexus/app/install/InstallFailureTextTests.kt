package com.skaymer.gryonixnexus.app.install

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The failure text, with the wiring taken out */
class InstallFailureTextTests {
    private val liveTail = """
        Command failed (exit 1): install
        GRYONIXNEXUS_STEP 1/11

        ==> Checking that the ports these services need are free
        GRYONIXNEXUS_PORTS_IN_USE
        ERROR: these ports are already in use on this server, so nothing was installed:
          Pi-hole: port 53/tcp is already used by the container «adguardhome» (compose project «adguardhome»)

        Free them — or remove the service that holds them — and run the script again.
        GRYONIXNEXUS_EXIT:1
    """.trimIndent()

    @Test
    fun `the scripts own protocol does not reach the reader`() {
        val readable = InstallFailureText.readable(liveTail)

        assertFalse("GRYONIXNEXUS" in readable, "a protocol token is on screen:\n$readable")
    }

    /** And everything a person can act on survives, verbatim */
    @Test
    fun `what the person has to act on is kept`() {
        val readable = InstallFailureText.readable(liveTail)

        assertTrue("Command failed (exit 1): install" in readable)
        assertTrue("Checking that the ports these services need are free" in readable)
        assertTrue("port 53/tcp is already used by the container «adguardhome»" in readable)
        assertTrue("Free them" in readable)
    }

    @Test
    fun `the stripped text does not start or end with a blank`() {
        val readable = InstallFailureText.readable(liveTail)

        assertFalse(readable.startsWith("\n") || readable.endsWith("\n"))
    }

    @Test
    fun `removing a marker does not leave a hole`() {
        val framed = "==> Installing services\n\nGRYONIXNEXUS_STEP 4/11\n\ndocker: permission denied"

        val readable = InstallFailureText.readable(framed)

        assertFalse("\n\n\n" in readable, "the text has a gap where a marker was:\n$readable")
        assertTrue("==> Installing services" in readable)
        assertTrue("docker: permission denied" in readable)
    }

    /** A message with no markers at all comes back untouched */
    @Test
    fun `an ordinary error is not rewritten`() {
        val plain = "docker: Cannot connect to the Docker daemon at unix:///var/run/docker.sock."

        assertEquals(plain, InstallFailureText.readable(plain))
    }
}
