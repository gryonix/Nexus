package com.skaymer.gryonixnexus.servercontrol

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PortForwardTest {
    private fun forward(id: String, server: String = "s", local: Int = 8080, host: String = "localhost", remote: Int = 80) =
        PortForward(id, server, localPort = local, remoteHost = host, remotePort = remote)

    @Test
    fun validForwardHasNoProblems() {
        val value = forward("a")
        assertEquals(emptyList(), value.problems(emptyList()))
        assertEquals("127.0.0.1:8080 → localhost:80", value.summary)
    }

    @Test
    fun rejectsBadPortsAndHost() {
        val problems = forward("a", local = 80, host = "a b", remote = 70000).problems(emptyList())
        assertEquals(
            setOf(PortForward.Problem.LOCAL_PORT, PortForward.Problem.REMOTE_HOST, PortForward.Problem.REMOTE_PORT),
            problems.toSet(),
        )
    }

    @Test
    fun duplicateLocalPortIsFlagged() {
        val first = forward("a", local = 5432)
        val second = forward("b", server = "t", local = 5432)
        assertEquals(listOf(PortForward.Problem.DUPLICATE_LOCAL_PORT), second.problems(listOf(first)))
        assertEquals(emptyList(), first.problems(listOf(first)))
    }

    @Test
    fun listEdits() {
        val one = forward("a", server = "s", local = 9000)
        val two = forward("b", server = "t", local = 9001)
        var all = PortForwardList.upserting(two, PortForwardList.upserting(one, emptyList()))
        all = PortForwardList.upserting(two.copy(name = "db"), all)
        assertEquals(2, all.size)
        assertEquals(listOf(one), PortForwardList.forServer("s", all))
        assertEquals(listOf(all[1]), PortForwardList.removingServer("s", all))
        assertTrue(PortForwardState.Running(0).isActive)
        assertFalse(PortForwardState.Failed("x").isActive)
    }
}
