package com.skaymer.gryonixnexus.servercontrol

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ServerProblemsTest {
    @Test
    fun eachFactMapsToItsProblem() {
        assertEquals(setOf(ServerProblem.UNREACHABLE), ServerHealthFacts("a", unreachable = true).problems)
        assertEquals(setOf(ServerProblem.DISK_ALMOST_FULL), ServerHealthFacts("a", diskFraction = 0.9).problems)
        assertEquals(emptySet(), ServerHealthFacts("a", diskFraction = 0.89).problems)
        assertEquals(setOf(ServerProblem.SERVICE_DOWN), ServerHealthFacts("a", servicesDown = 2).problems)
        assertEquals(setOf(ServerProblem.UPDATES_PENDING), ServerHealthFacts("a", updatesPending = 5).problems)
        assertEquals(emptySet(), ServerHealthFacts("a", servicesDown = 0, updatesPending = 0).problems)
    }

    @Test
    fun countsAndFilter() {
        val a = ServerHealthFacts("a", unreachable = true)
        val b = ServerHealthFacts("b", diskFraction = 0.95, updatesPending = 3)
        val c = ServerHealthFacts("c", diskFraction = 0.2)
        val counts = ServerProblems.counts(listOf(a, b, c))
        assertEquals(1, counts[ServerProblem.UNREACHABLE])
        assertEquals(1, counts[ServerProblem.DISK_ALMOST_FULL])
        assertEquals(1, counts[ServerProblem.UPDATES_PENDING])
        assertNull(counts[ServerProblem.SERVICE_DOWN])
        assertEquals(setOf("b"), ServerProblems.ids(ServerProblem.DISK_ALMOST_FULL, listOf(a, b, c)))
    }

    @Test
    fun offlineServersSinkKeepingOrder() {
        val offline = setOf("b", "d")
        assertEquals(listOf("a", "c", "e", "b", "d"), ServerListOrdering.ordered(listOf("a", "b", "c", "d", "e")) { it in offline })
    }
}
