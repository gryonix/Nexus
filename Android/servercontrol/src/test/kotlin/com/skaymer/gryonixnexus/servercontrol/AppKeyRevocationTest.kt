package com.skaymer.gryonixnexus.servercontrol

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class AppKeyRevocationTest {
    private val key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyBodyForTests0123456789 gryonixnexus"
    private val body = "AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyBodyForTests0123456789"

    @Test
    fun theKeyBodyIsTheSecondField() {
        assertEquals(body, AppKeyRevocation.keyBody(key))
    }

    @Test
    fun anythingThatCouldBreakTheQuotingIsRefused() {
        assertNull(AppKeyRevocation.keyBody("ssh-ed25519 AAAA'; rm -rf ~ #0123456789"))
        assertNull(AppKeyRevocation.keyBody("ssh-ed25519"))
        assertNull(AppKeyRevocation.keyBody(""))
    }

    @Test
    fun onlyKeyAndNoPasswordIsTheLastWayIn() {
        assertTrue(AppKeyRevocation.parse("present=yes\nothers=0\npassword=no\n")!!.isLastWayIn)
        assertTrue(AppKeyRevocation.parse("present=yes\nothers=0\npassword=unknown")!!.isLastWayIn)
    }

    @Test
    fun anotherKeyOrPasswordLoginLeavesAWayIn() {
        assertFalse(AppKeyRevocation.parse("present=yes\nothers=2\npassword=no")!!.isLastWayIn)
        assertFalse(AppKeyRevocation.parse("present=yes\nothers=0\npassword=yes")!!.isLastWayIn)
        assertFalse(AppKeyRevocation.parse("present=no\nothers=0\npassword=no")!!.isLastWayIn)
    }

    @Test
    fun anUnrelatedAnswerIsNotACheck() {
        assertNull(AppKeyRevocation.parse("bash: line 1: grep: command not found"))
    }

    @Test
    fun theScriptsCarryOnlyTheQuotedBody() {
        val remove = AppKeyRevocation.removeScript(body)
        assertTrue(remove.contains("grep -vF '$body'"), remove)
        assertTrue(remove.contains("chmod 600"), remove)
        assertFalse(remove.contains("gryonixnexus"))
        val check = AppKeyRevocation.checkScript(body)
        assertTrue(check.contains("passwordauthentication"))
        assertTrue(check.contains("grep -v '^[[:space:]]*\$'"), check)
    }

    @Test
    fun machinesBehindOthersAreHandledFirst() {
        fun node(id: String, through: String? = null) = DeploymentNode(
            id = id, name = id, endpoint = HostEndpoint(host = "203.0.113.4", user = "ops"),
            capabilities = setOf(NodeCapability.WORKER), routedThrough = through,
        )
        val order = AppKeyRevocation.removalOrder(listOf(node("orion"), node("draco", "orion"), node("lyra", "draco")))
        assertEquals(listOf("lyra", "draco", "orion"), order.map { it.name })
    }
}
