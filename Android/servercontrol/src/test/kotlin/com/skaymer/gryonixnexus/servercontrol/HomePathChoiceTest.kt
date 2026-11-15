package com.skaymer.gryonixnexus.servercontrol

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

/** The path choice decides which links are tried */
class HomePathChoiceTest {
    @Test
    fun `automatic tries everything`() {
        assertEquals(HomePathChoice.Plan(true, true, true), HomePathChoice.AUTOMATIC.plan)
    }

    @Test
    fun `through the VPS never touches the local network`() {
        val plan = HomePathChoice.THROUGH_VPS.plan
        assertFalse(plan.localFirst)
        assertFalse(plan.localLastResort)
        assertTrue(plan.usesVPS)
    }

    @Test
    fun `over the local network never uses the VPS`() {
        val plan = HomePathChoice.LOCAL_NETWORK.plan
        assertTrue(plan.localFirst)
        assertFalse(plan.usesVPS)
    }

    @Test
    fun `an unknown stored value means automatic`() {
        assertEquals(HomePathChoice.AUTOMATIC, HomePathChoice.from(null))
        assertEquals(HomePathChoice.AUTOMATIC, HomePathChoice.from("nonsense"))
        assertEquals(HomePathChoice.LOCAL_NETWORK, HomePathChoice.from("localNetwork"))
    }
}
