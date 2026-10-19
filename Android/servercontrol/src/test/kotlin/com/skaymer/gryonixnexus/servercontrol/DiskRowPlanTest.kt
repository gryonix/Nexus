package com.skaymer.gryonixnexus.servercontrol

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class DiskRowPlanTest {
    private fun mount(target: String, used: Long = 1, size: Long = 10) =
        DiskMount(
            target = target,
            sizeBytes = size,
            usedBytes = used,
            usedPercent = (used * 100 / size).toInt(),
        )

    @Test
    fun `the root filesystem is the only primary row`() {
        val plan = DiskRowPlan.make(listOf(mount("/boot"), mount("/"), mount("/boot/efi")))
        assertEquals(listOf("/"), plan.primary.map { it.target })
        assertEquals(listOf("/boot", "/boot/efi"), plan.others.map { it.target })
        assertFalse(plan.namesPrimaryByTarget)
    }

    @Test
    fun `the other volumes are kept behind their own line`() {
        val plan = DiskRowPlan.make(listOf(mount("/"), mount("/boot"), mount("/srv")))
        assertEquals(listOf("/"), plan.primary.map { it.target })
        assertEquals(listOf("/boot", "/srv"), plan.others.map { it.target })
        assertFalse(
            plan.namesPrimaryByTarget,
            "a root was reported, so the row is called 'Disk' and not '/'",
        )
    }

    @Test
    fun `a host with no root mount lists every mount it did report`() {
        val plan = DiskRowPlan.make(listOf(mount("/mnt/data"), mount("/mnt/backup")))
        assertEquals(listOf("/mnt/data", "/mnt/backup"), plan.primary.map { it.target })
        assertTrue(
            plan.namesPrimaryByTarget,
            "three rows all called 'Disk' are not three answers",
        )
        assertEquals(
            emptyList<DiskMount>(), plan.others,
            "everything is already primary; nothing is left to fold",
        )
    }

    @Test
    fun `no mounts at all plans no rows`() {
        val plan = DiskRowPlan.make(emptyList())
        assertEquals(emptyList<DiskMount>(), plan.primary)
        assertEquals(emptyList<DiskMount>(), plan.others)
    }

    @Test
    fun `the hosts own order is kept`() {
        val plan = DiskRowPlan.make(listOf(mount("/"), mount("/srv"), mount("/boot")))
        assertEquals(listOf("/srv", "/boot"), plan.others.map { it.target })
    }
}
