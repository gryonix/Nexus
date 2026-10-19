package com.skaymer.gryonixnexus.agentcontrol

import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `AgentChannelGateTests` */
class AgentChannelGateTest {
    /** Counts concurrent holders, remembering the peak */
    private class Peak {
        private val current = AtomicInteger(0)
        private val highest = AtomicInteger(0)

        fun enter() {
            val now = current.incrementAndGet()
            highest.updateAndGet { maxOf(it, now) }
        }

        fun leave() = current.decrementAndGet()

        fun current() = current.get()
        fun highest() = highest.get()
    }

    @Test
    fun `never exceeds the limit under fan-out`() = runBlocking {
        val gate = AgentChannelGate(limit = 4)
        val peak = Peak()

        val jobs = (0 until 32).map {
            launch(Dispatchers.Default) {
                gate.withSlot {
                    peak.enter()
                    // Long enough that the coroutines genuinely overlap.
                    delay(20)
                    peak.leave()
                }
            }
        }
        jobs.forEach { it.join() }

        assertTrue(peak.highest() <= 4, "more channels were open at once than sshd allows")
        assertTrue(peak.highest() > 1, "the gate serialized everything — the fan-out was not real")
        assertEquals(0, peak.current(), "a slot was leaked")
    }

    @Test
    fun `a throwing body releases its slot`() = runBlocking {
        class Boom : Exception()
        val gate = AgentChannelGate(limit = 1)

        repeat(3) {
            val error = runCatching { gate.withSlot { throw Boom() } }.exceptionOrNull()
            assertTrue(error is Boom, "unexpected error: $error")
        }

        assertTrue(gate.withSlot { true })
    }

    @Test
    fun `the limit is the SSH runner's ceiling`() {
        // Both numbers answer to the same sshd MaxSessions; drift between them
        // would mean one route quietly opening more channels than the other.
        assertEquals(4, AgentChannelGate.DEFAULT_LIMIT)
    }

    /**
     * Not in the Swift twin, and it is here because Kotlin's gate has something
     * Swift's hand-rolled queue does not: a registry. A gate PER SCREEN stopped
     * counting the moment the SSH session became shared — three screens holding
     * four each on one connection is twelve channels against a MaxSessions of
     * ten.
     */
    @Test
    fun `one deployment gets one gate however many screens ask for it`() {
        val first = AgentChannelGate.shared("deployment-a")
        assertTrue(first === AgentChannelGate.shared("deployment-a"))
        assertTrue(first !== AgentChannelGate.shared("deployment-b"))
    }
}
