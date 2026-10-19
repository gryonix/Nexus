package com.skaymer.gryonixnexus.app.install

import com.skaymer.gryonixnexus.catalog.storage.RaidPlan
import com.skaymer.gryonixnexus.catalog.storage.ServerDisk
import com.skaymer.gryonixnexus.catalog.storage.ServerHardware
import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.core.ArtifactKind
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class StoragePreparationTests {
    private fun disk(name: String, kind: ServerDisk.Kind) = ServerDisk(
        name = name, path = "/dev/$name", sizeBytes = 1_000_000_000, kind = kind, model = "",
        mountpoints = emptyList(), filesystems = emptyList(), partitionCount = 0, raidMember = false,
    )

    private val hardware = ServerHardware(
        cpuCores = 4, memoryBytes = 8_000_000_000, architecture = "x86_64", rootFreeBytes = 50_000_000_000,
        disks = listOf(disk("nvme0n1", ServerDisk.Kind.NVME), disk("sdb", ServerDisk.Kind.HDD), disk("sdc", ServerDisk.Kind.HDD)),
    )

    private val target = InstallTarget(
        kind = InstallTarget.Kind.SINGLE,
        script = Artifact(fileName = "setup.sh", kind = ArtifactKind.SHELL_SCRIPT, contents = "      - /opt/immich/postgres:/var/lib/postgresql/data\n", summary = ""),
        slot = DeploymentNode.LegacySlot.VPS,
        address = "203.0.113.10",
        connection = InstallTarget.Connection.Ok,
        hardware = hardware,
    )

    @Test
    fun `a raid waits for enough disks and the typed confirmation`() {
        val raid = target.copy(storage = StorageChoice(buildsRaid = true, raidDisks = setOf("/dev/sdb")))
        assertFalse(raid.isReady)
        val twoDisks = raid.copy(storage = raid.storage.copy(raidDisks = setOf("/dev/sdb", "/dev/sdc")))
        assertFalse(twoDisks.isReady)
        assertTrue(twoDisks.copy(storage = twoDisks.storage.copy(confirmed = true)).isReady)
    }

    @Test
    fun `the raid is built before the cache disk, with hot paths from the script`() {
        val both = target.copy(storage = StorageChoice(
            fastDisk = "/dev/nvme0n1", buildsRaid = true, raidLevel = RaidPlan.Level.RAID1,
            raidDisks = setOf("/dev/sdb", "/dev/sdc"), confirmed = true,
        ))
        assertEquals(listOf(StorageStep.Kind.RAID, StorageStep.Kind.CACHE), both.storageSteps.map { it.kind })
        assertTrue("bind_fast '/opt/immich/postgres'" in both.storageSteps[1].script)
        assertTrue(target.storageSteps.isEmpty())
    }
}
