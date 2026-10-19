package com.skaymer.gryonixnexus.catalog.storage

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ArrayChangeTest {
    private fun fixture(name: String): String =
        requireNotNull(javaClass.getResource("/storage/$name")) { name }.readText()

    private fun healthy(): ServerHardware = requireNotNull(ServerHardware.parse(fixture("probe-healthy-arrays.txt")))

    private fun array(kind: StorageArray.Kind, hardware: ServerHardware) =
        StorageArray.all(hardware).first { it.kind == kind }

    private fun JsonObject.text(key: String) = getValue(key).jsonPrimitive.content
    private fun JsonObject.list(key: String) = getValue(key).jsonArray.map { it.jsonPrimitive.content }

    /** Golden file name to the spec that makes it */
    private fun cases(): Map<String, ArrayChangeSpec> =
        Json.parseToJsonElement(fixture("array-change-cases.json")).jsonArray.associate { element ->
            val case = element.jsonObject
            case.text("golden") to ArrayChangeSpec(
                action = requireNotNull(ArrayChange.Action.of(case.text("action"))),
                kind = StorageArray.Kind.valueOf(case.text("kind").uppercase()),
                address = case.text("address"), name = case.text("name"), level = case.text("level"),
                member = case.text("member"), disks = case.list("disks"),
                devices = case.getValue("devices").jsonPrimitive.int,
                newLevel = case.getValue("newLevel").jsonPrimitive.int,
                members = case.list("members"), checkDisks = case.list("checkDisks"),
                identities = case.getValue("identities").jsonArray.map {
                    val identity = it.jsonObject
                    DiskIdentity(identity.text("path"), identity.text("serial"), identity.getValue("sizeBytes").jsonPrimitive.long)
                },
            )
        }

    @Test
    fun `every change script matches the Swift golden`() {
        val all = cases()
        assertEquals(28, all.size)
        all.forEach { (golden, spec) -> assertEquals(fixture(golden), spec.script(), golden) }
    }

    @Test
    fun `the probe reads serials and the disk job`() {
        val hardware = healthy()
        assertEquals("WD-WCC4E1AAAAA1", hardware.disks.first { it.name == "sdb" }.serial)
        val job = requireNotNull(hardware.diskJob)
        assertEquals("grow", job.action)
        assertEquals("gryonixnexus", job.target)
        assertEquals(DiskJob.Outcome.RUNNING, job.outcome)
        assertEquals(listOf("mdadm: Need to wait for the reshape"), job.lastLines)
        assertEquals(listOf("sdi", "sdj"), RaidPlan.candidates(hardware).map { it.name })
    }

    @Test
    fun `a job that ended says how`() {
        val done = DiskJob.parse("inactive|GRYONIXNEXUS_DISK_JOB_START remove data 100|moved|GRYONIXNEXUS_DISK_JOB_DONE 200|")
        assertEquals(DiskJob.Outcome.DONE, done?.outcome)
        assertEquals(listOf("moved"), done?.lastLines)
        assertEquals(true, done?.isRecent(1000))
        assertEquals(false, done?.isRecent(400_000))
        val failed = DiskJob.parse("failed|GRYONIXNEXUS_DISK_JOB_START grow md 100|oops|GRYONIXNEXUS_DISK_JOB_FAILED 150|")
        assertEquals(DiskJob.Outcome.FAILED, failed?.outcome)
        val cut = DiskJob.parse("inactive|GRYONIXNEXUS_DISK_JOB_START grow md 100|halfway|")
        assertEquals(DiskJob.Outcome.FAILED, cut?.outcome)
        assertNull(DiskJob.parse("inactive||"))
    }

    @Test
    fun `each kind offers only what it can do`() {
        val hardware = healthy()
        val md = array(StorageArray.Kind.MD, hardware)
        assertEquals(RaidPlan.Level.RAID5, md.raidLevel)
        assertEquals(
            listOf("add-spare", "grow", "replace", "detach", "change-level", "check", "delete"),
            ArrayChange.actions(md, hardware).map { it.raw },
        )
        assertEquals(listOf(RaidPlan.Level.RAID6), ArrayChange.levels(md))
        val pool = array(StorageArray.Kind.ZFS, hardware)
        assertEquals(RaidPlan.Level.RAID1, pool.raidLevel)
        assertEquals(
            listOf("add-spare", "grow", "replace", "detach", "remove", "check", "delete"),
            ArrayChange.actions(pool, hardware).map { it.raw },
        )
        val btrfs = array(StorageArray.Kind.BTRFS, hardware)
        assertEquals(listOf("grow", "replace", "change-level", "check", "delete"), ArrayChange.actions(btrfs, hardware).map { it.raw })
        assertEquals(listOf(RaidPlan.Level.RAID0), ArrayChange.levels(btrfs))
    }

    @Test
    fun `a broken array can only be deleted`() {
        val degraded = StorageArray.all(requireNotNull(ServerHardware.parse(fixture("probe-raid-degraded.txt")))).first()
        val hardware = healthy()
        assertEquals(listOf(ArrayChange.Action.DELETE), ArrayChange.actions(degraded, hardware))
        val cache = StorageArray(
            name = RaidPlan.CACHE_NAME, uuid = null, device = "/dev/md126", level = "raid1",
            members = listOf("/dev/sdb", "/dev/sdc"), failed = emptyList(), slots = 2, working = 2,
            state = StorageArray.State.Clean, mountpoint = null, filesystem = null,
        )
        assertFalse(ArrayChange.Action.DELETE in ArrayChange.actions(cache, hardware))
    }

    @Test
    fun `the preview shows space and protection`() {
        val hardware = healthy()
        val sdi = hardware.disks.first { it.name == "sdi" }
        val md = array(StorageArray.Kind.MD, hardware)
        val grown = ArrayChange(ArrayChange.Action.GROW, md, disks = listOf(sdi)).preview(hardware)
        assertEquals(2 * 4_000_787_030_016, grown.usableBefore)
        assertEquals(3 * 4_000_787_030_016, grown.usableAfter)
        assertEquals(1, grown.failuresAfter)
        assertTrue(grown.takesLong)
        val detached = ArrayChange(ArrayChange.Action.DETACH, md, member = "/dev/sdc").preview(hardware)
        assertEquals(0, detached.failuresAfter)
        assertFalse(detached.takesLong)
        val pool = array(StorageArray.Kind.ZFS, hardware)
        val third = ArrayChange(ArrayChange.Action.GROW, pool, disks = listOf(sdi)).preview(hardware)
        assertEquals(third.usableBefore, third.usableAfter)
        assertEquals(listOf(1, 2), listOf(third.failuresBefore, third.failuresAfter))
        val btrfs = array(StorageArray.Kind.BTRFS, hardware)
        val striped = ArrayChange(ArrayChange.Action.CHANGE_LEVEL, btrfs, level = RaidPlan.Level.RAID0).preview(hardware)
        assertEquals(2 * striped.usableBefore, striped.usableAfter)
        assertEquals(0, striped.failuresAfter)
    }

    @Test
    fun `the spec from a real array matches the shared case`() {
        val hardware = healthy()
        val sdi = hardware.disks.first { it.name == "sdi" }
        val byName = cases()
        val md = array(StorageArray.Kind.MD, hardware)
        assertEquals(byName["change-md-grow.sh"], ArrayChange(ArrayChange.Action.GROW, md, disks = listOf(sdi)).spec(hardware))
        assertEquals(
            byName["change-md-replace.sh"],
            ArrayChange(ArrayChange.Action.REPLACE, md, member = "/dev/sdc", disks = listOf(sdi)).spec(hardware),
        )
        val pool = array(StorageArray.Kind.ZFS, hardware)
        assertEquals(byName["change-zfs-grow-mirror.sh"], ArrayChange(ArrayChange.Action.GROW, pool, disks = listOf(sdi)).spec(hardware))
        assertEquals(byName["change-zfs-delete.sh"], ArrayChange(ArrayChange.Action.DELETE, pool).spec(hardware))
        val btrfs = array(StorageArray.Kind.BTRFS, hardware)
        assertEquals(
            byName["change-btrfs-replace.sh"],
            ArrayChange(ArrayChange.Action.REPLACE, btrfs, member = "/dev/sdh", disks = listOf(sdi)).spec(hardware),
        )
    }

    @Test
    fun `new kinds of array and disk work match the Swift golden`() {
        val hardware = healthy()
        val free = RaidPlan.candidates(hardware)
        val named = RaidPlan.storage(RaidPlan.Level.RAID1, free, hardware, StorageArray.Kind.ZFS)
        assertEquals("gryonixnexus2", named.name)
        assertEquals(fixture("zfs-create.sh"), named.script())
        val four = hardware.disks.filter { it.name in setOf("sdb", "sdc", "sdi", "sdj") }
        val pairs = RaidPlan(RaidPlan.Level.RAID10, four, "gryonixnexus2", "/srv/gryonixnexus-storage2", StorageArray.Kind.ZFS)
        assertEquals(1, pairs.survivableFailures)
        assertEquals(fixture("zfs-create-pairs.sh"), pairs.script())
        val btrfs = RaidPlan(RaidPlan.Level.RAID1, free, "gryonixnexus2", "/srv/gryonixnexus-storage2", StorageArray.Kind.BTRFS)
        assertEquals(1, btrfs.survivableFailures)
        assertFalse(RaidPlan(RaidPlan.Level.RAID5, free + free, kind = StorageArray.Kind.BTRFS).isValid)
        assertEquals(fixture("btrfs-create.sh"), btrfs.script())
        val format = DiskFormatPlan.plan(free[0], DiskFormatPlan.Filesystem.EXT4, hardware)
        assertEquals("/srv/disk-sdi", format.mountPoint)
        assertEquals("gnx-sdi", format.label)
        assertEquals(fixture("disk-format.sh"), format.script())
        assertEquals(
            fixture("disk-format-xfs.sh"),
            DiskFormatPlan("/dev/sdj", DiskFormatPlan.Filesystem.XFS, "gnx-sdj", "/srv/disk-sdj").script(),
        )
        assertEquals(fixture("disk-release.sh"), DiskReleasePlan("/srv/disk-sdi").script())
        assertEquals(fixture("disk-blink.sh"), DiskBlink.script("/dev/sdi"))
    }
}
