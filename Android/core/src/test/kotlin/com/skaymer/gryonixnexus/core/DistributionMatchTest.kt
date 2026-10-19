package com.skaymer.gryonixnexus.core

import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The Kotlin twin of `testTheAppSideMatcherAgreesWithTheShellGuard` */
class DistributionMatchTest {
    @Test
    fun `a host running exactly what the script was built for is accepted`() {
        assertTrue(DistributionMatch.accepts(expected = "debian", id = "debian", idLike = ""))
        assertTrue(DistributionMatch.accepts(expected = "ubuntu", id = "ubuntu", idLike = ""))
    }

    @Test
    fun `a derivative is accepted through ID_LIKE`() {
        assertTrue(DistributionMatch.accepts(expected = "debian", id = "devuan", idLike = "debian"))
        assertTrue(DistributionMatch.accepts(expected = "ubuntu", id = "pop", idLike = "ubuntu debian"))
    }

    /** Ubuntu lists debian in ID_LIKE */
    @Test
    fun `a distribution we model separately never passes as another`() {
        assertFalse(DistributionMatch.accepts(expected = "debian", id = "ubuntu", idLike = "debian"))
        assertFalse(DistributionMatch.accepts(expected = "ubuntu", id = "debian", idLike = ""))
    }

    @Test
    fun `an unrelated distribution is refused`() {
        assertFalse(DistributionMatch.accepts(expected = "debian", id = "fedora", idLike = "rhel"))
        assertFalse(DistributionMatch.accepts(expected = "ubuntu", id = "arch", idLike = ""))
    }

    /** Not in the Swift twin */
    @Test
    fun `ID_LIKE is matched by whole word, not by substring`() {
        assertFalse(DistributionMatch.accepts(expected = "debian", id = "weird", idLike = ""))
        assertFalse(DistributionMatch.accepts(expected = "ubuntu", id = "weird", idLike = "ubuntu-core"))
        assertTrue(DistributionMatch.accepts(expected = "ubuntu", id = "weird", idLike = "x ubuntu y"))
    }
}
