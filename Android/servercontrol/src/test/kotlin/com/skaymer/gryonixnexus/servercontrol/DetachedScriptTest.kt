package com.skaymer.gryonixnexus.servercontrol

import java.util.Base64
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class DetachedScriptTest {
    @Test
    fun theScriptRunsFromATemporaryFileAndIsRemoved() {
        val command = DetachedScript.command("echo hi\n", elevated = true)
        assertTrue(Base64.getEncoder().encodeToString("echo hi\n".toByteArray()) in command)
        assertTrue("sudo -n bash \"\$f\"" in command)
        assertTrue("rm -f \"\$f\"" in command)
        assertFalse("sudo" in DetachedScript.command("true", elevated = false))
    }

    @Test
    fun theShellMatchesTheAppleSide() {
        val command = DetachedScript.command("true", elevated = false)
        assertEquals(
            "f=\"\$(mktemp)\" && printf '%s' 'dHJ1ZQ==' | base64 -d > \"\$f\" && ( bash \"\$f\"; rc=\$?; rm -f \"\$f\"; exit \$rc )",
            command,
        )
    }

    @Test
    fun theOutputIsReadFromTheMeasurementJob() = runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("measure-speed-100", stdout = "down 1 200\nup 2 200\nDONE\n")
        val followed = DetachedScript.output(
            "true", elevated = false, subject = "speed", runner = runner, host = SSHHostID.VPS,
            retryDelay = 1.milliseconds, now = 100,
        )
        assertEquals("down 1 200\nup 2 200\nDONE\n", followed.output)
        assertEquals(0, followed.exitCode)
    }
}
