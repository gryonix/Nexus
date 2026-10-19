package com.skaymer.gryonixnexus.servercontrol

import kotlinx.coroutines.test.runTest
import kotlin.test.assertEquals
import org.junit.jupiter.api.Test

class AdminLockdownRestoreTest {
    private class Recording : AdminLockdownManaging {
        val calls = mutableListOf<String>()

        override suspend fun status(): AdminLockdownState = AdminLockdownState.Off

        override suspend fun set(enabled: Boolean): AdminLockdownState {
            calls += if (enabled) "on" else "off"
            return if (enabled) AdminLockdownState.All else AdminLockdownState.Off
        }

        override suspend fun set(hosts: List<String>): AdminLockdownState {
            calls += "only " + hosts.joinToString(" ")
            return AdminLockdownState.Only(hosts.toSet())
        }
    }

    @Test
    fun `each state is put back the way it was read`() = runTest {
        val lockdown = Recording()
        lockdown.restore(AdminLockdownState.All)
        lockdown.restore(AdminLockdownState.Only(setOf("b.example.net", "a.example.net")))
        lockdown.restore(AdminLockdownState.Off)
        assertEquals(listOf("on", "only a.example.net b.example.net", "off"), lockdown.calls)
    }
}
