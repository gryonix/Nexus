package com.skaymer.gryonixnexus.catalog.storage

import com.skaymer.gryonixnexus.catalog.ServerRequirements
import com.skaymer.gryonixnexus.catalog.ServiceContext
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ServerStorageTest {
    private fun fixture(name: String): String =
        requireNotNull(javaClass.getResource("/storage/$name")) { name }.readText()

    private fun hardware(): ServerHardware =
        requireNotNull(ServerHardware.parse(fixture("probe-output.txt")))

    @Test
    fun `the probe reads cores memory and every real disk`() {
        val hardware = hardware()
        assertEquals(8, hardware.cpuCores)
        assertEquals(16_777_216_000, hardware.memoryBytes)
        assertEquals("x86_64", hardware.architecture)
        assertEquals(listOf("sda", "nvme0n1", "sdb", "sdc", "sdd"), hardware.disks.map { it.name })
        assertEquals(
            listOf(ServerDisk.Kind.SSD, ServerDisk.Kind.NVME, ServerDisk.Kind.HDD, ServerDisk.Kind.HDD, ServerDisk.Kind.SSD),
            hardware.disks.map { it.kind },
        )
        assertTrue(hardware.disks[0].isSystem)
        assertTrue(hardware.disks[1].isBlank)
        assertFalse(hardware.disks[3].isBlank)
        assertEquals("/mnt/fast", hardware.disks[4].dataMount)
    }

    @Test
    fun `a real Debian server parses`() {
        val live = requireNotNull(ServerHardware.parse(fixture("probe-live-debian13.txt")))
        assertEquals(12, live.cpuCores)
        assertEquals(listOf("vda"), live.disks.map { it.name })
        assertTrue(live.disks[0].isSystem)
        assertEquals(ServerDisk.Kind.HDD, live.disks[0].kind)
        assertTrue(FastStoragePlan.candidates(live).isEmpty())
        assertTrue(RaidPlan.candidates(live).isEmpty())
    }

    @Test
    fun `candidates never offer the system disk`() {
        val hardware = hardware()
        assertEquals(listOf("nvme0n1", "sdd"), FastStoragePlan.candidates(hardware).map { it.name })
        assertEquals(listOf("nvme0n1", "sdb", "sdc"), RaidPlan.candidates(hardware).map { it.name })
    }

    @Test
    fun `the verdict names what is short`() {
        val hardware = hardware()
        assertEquals(HardwareVerdict.Level.FITS, HardwareVerdict.judge(hardware, ServerRequirements(4096, 20, true)).level)
        val short = HardwareVerdict.judge(hardware, ServerRequirements(32_768, 55, true))
        assertEquals(HardwareVerdict.Level.DOES_NOT_FIT, short.level)
        assertEquals(listOf(HardwareVerdict.Level.DOES_NOT_FIT, HardwareVerdict.Level.TIGHT), short.findings.map { it.level })
    }

    @Test
    fun `hot paths come from the compose files`() {
        val context = ServiceContext(domain = "example.com", sshUser = "admin")
        val files = listOf(ServiceID.IMMICH, ServiceID.NEXTCLOUD).mapNotNull {
            ServiceRegistry.service(it)?.composeFile(context)
        }
        assertEquals(
            listOf("/opt/immich/ml-cache", "/opt/immich/postgres", "/opt/nextcloud/db"),
            FastStoragePlan.hotPaths(files),
        )
    }

    @Test
    fun `scripts match the Swift golden`() {
        val hardware = hardware()
        val hot = listOf("/opt/immich/postgres", "/opt/nextcloud/db")
        assertEquals(fixture("fast-blank.sh"), FastStoragePlan(hardware.disks[1], hot).script())
        assertEquals(fixture("fast-mounted.sh"), FastStoragePlan(hardware.disks[4], hot).script())
        val raid = RaidPlan(RaidPlan.Level.RAID1, listOf(hardware.disks[2], hardware.disks[3]))
        assertTrue(raid.isValid)
        assertEquals(4_000_787_030_016, raid.usableBytes)
        assertFalse(RaidPlan(RaidPlan.Level.RAID5, listOf(hardware.disks[2])).isValid)
        assertEquals(8L, RaidPlan.Level.RAID6.usableBytes(listOf(4, 4, 4, 5)))
        assertEquals(fixture("raid1.sh"), raid.script())
    }

    @Test
    fun `the guard carries the serial and size the app saw`() {
        val hardware = hardware()
        val named = hardware.disks[2].copy(serial = "WD WCC4E1 77")
        val raid = RaidPlan(RaidPlan.Level.RAID1, listOf(named, hardware.disks[3]))
        assertEquals(fixture("raid1-serials.sh"), raid.script())
        assertEquals(DiskIdentity("/dev/sdb", "WDWCC4E177", 4_000_787_030_016), named.identity)
    }

    private fun arrays(name: String) = StorageArray.all(requireNotNull(ServerHardware.parse(fixture(name))))

    @Test
    fun `a second array takes the next free name and mount`() {
        val empty = requireNotNull(ServerHardware.parse(fixture("probe-output.txt")))
        val first = RaidPlan.storage(RaidPlan.Level.RAID1, emptyList(), empty)
        assertEquals("gryonixnexus", first.name)
        assertEquals("/srv/gryonixnexus-storage", first.mountPoint)
        val taken = requireNotNull(ServerHardware.parse(fixture("probe-raid-stopped.txt")))
        val second = RaidPlan.storage(RaidPlan.Level.RAID1, emptyList(), taken)
        assertEquals("gryonixnexus2", second.name)
        assertEquals("/srv/gryonixnexus-storage2", second.mountPoint)
        assertEquals("/dev/md/gryonixnexus2", second.device)
    }

    @Test
    fun `an array left by an earlier install is found stopped`() {
        val found = arrays("probe-raid-stopped.txt")
        assertEquals(1, found.size)
        assertEquals("gryonixnexus", found[0].name)
        assertEquals(StorageArray.State.Stopped, found[0].state)
        assertEquals("dd96909c:ae315ffe:3a59f52c:051376ba", found[0].uuid)
        assertEquals("/dev/md/gryonixnexus", found[0].address)
    }

    @Test
    fun `a failed member makes the array degraded and is not a second array`() {
        val found = arrays("probe-raid-degraded.txt")
        assertEquals(1, found.size)
        assertEquals(StorageArray.State.Degraded, found[0].state)
        assertEquals(listOf("/dev/vdd"), found[0].failed)
        assertEquals(listOf("/dev/vdb"), found[0].members)
        assertEquals("/dev/md127", found[0].device)
        assertTrue(found[0].needsAttention)
    }

    @Test
    fun `a rebuild shows its progress`() {
        val found = arrays("probe-raid-rebuilding.txt")
        assertEquals(1, found.size)
        assertTrue(found[0].state is StorageArray.State.Rebuilding)
    }

    @Test
    fun `recovery scripts match the Swift golden`() {
        val stopped = arrays("probe-raid-stopped.txt")[0]
        assertEquals(fixture("raid-import.sh"), RaidImportPlan(stopped).script())
        val degraded = arrays("probe-raid-degraded.txt")[0]
        val degradedHardware = requireNotNull(ServerHardware.parse(fixture("probe-raid-degraded.txt")))
        val spare = RaidRepairPlan.candidates(degradedHardware, degraded).first()
        assertEquals(fixture("raid-repair.sh"), RaidRepairPlan(degraded, spare).script())
        val ssds = hardware()
        val pair = listOf(ssds.disks[1], ssds.disks[4])
        assertEquals(fixture("cache-mirror.sh"), RaidPlan.cacheMirror(pair).script())
        assertEquals(
            fixture("fast-mirror.sh"),
            FastStoragePlan(FastStoragePlan.Target.Device(RaidPlan.cacheMirror(pair).device), listOf("/opt/immich/postgres")).script(),
        )
    }

    @Test
    fun `a TrueNAS pool left on the disks is found and its disks are not offered`() {
        val hardware = requireNotNull(ServerHardware.parse(fixture("probe-zfs-truenas.txt")))
        val found = StorageArray.all(hardware)
        assertEquals(1, found.size)
        assertEquals(StorageArray.Kind.ZFS, found[0].kind)
        assertEquals("tank", found[0].name)
        assertEquals(StorageArray.State.Stopped, found[0].state)
        assertEquals(listOf("/dev/sda2", "/dev/sdb2"), found[0].members)
        assertEquals(emptyList<String>(), RaidPlan.candidates(hardware).map { it.path })
        assertEquals(fixture("zfs-import.sh"), RaidImportPlan(found[0]).script())
    }

    @Test
    fun `every popular kind of array is found`() {
        val hardware = requireNotNull(ServerHardware.parse(fixture("probe-many-arrays.txt")))
        val found = StorageArray.all(hardware).groupBy { it.kind }
        assertEquals(1, found[StorageArray.Kind.MD]?.size, "md on partitions is one array")
        assertEquals("/srv/md", found[StorageArray.Kind.MD]?.first()?.mountpoint)
        val pool = requireNotNull(found[StorageArray.Kind.ZFS]?.single())
        assertEquals("raidz1", pool.level)
        assertEquals(StorageArray.State.Degraded, pool.state)
        assertEquals(listOf("/dev/sda2", "/dev/sdb2"), pool.members)
        assertEquals(listOf("9147389209417539263"), pool.failed)
        assertEquals("/mnt/tank", pool.mountpoint)
        val btrfs = requireNotNull(found[StorageArray.Kind.BTRFS]?.single())
        assertEquals("raid1", btrfs.level)
        assertEquals("/srv/data", btrfs.mountpoint)
        val lvm = requireNotNull(found[StorageArray.Kind.LVM]?.single())
        assertEquals("vg0-data", lvm.name)
        assertEquals(listOf("/dev/sde", "/dev/sdf"), lvm.members)
        assertEquals(StorageArray.State.Clean, lvm.state)
        assertEquals(listOf("PERC H730 Mini"), found[StorageArray.Kind.HARDWARE]?.map { it.name })
        assertEquals(listOf("/dev/sdj"), pool.spares)
        assertEquals(listOf("/dev/sdi"), RaidPlan.candidates(hardware).map { it.path }, "a pool's spare is never offered")
        val spare = hardware.disks.first { it.path == "/dev/sdj" }
        assertEquals(fixture("zfs-replace.sh"), RaidRepairPlan(pool, spare).script())
    }

    @Test
    fun `a running server's hot directories are read from its compose files`() {
        val probe = listOf(
            "### /opt/immich/docker-compose.yml", "services:", "  database:", "    volumes:",
            "      - /opt/immich/postgres:/var/lib/postgresql/data", "      - /opt/immich/upload:/usr/src/app/upload",
            "### /opt/homeassistant/docker-compose.yml", "services:", "  homeassistant:", "    volumes:",
            "      - /opt/homeassistant/config:/config",
            "### /opt/nextcloud/docker-compose.yml", "services:", "  db:", "    volumes:",
            "      - /opt/nextcloud/db:/var/lib/mysql", "  redis:", "    volumes:", "      - /opt/nextcloud/redis:/data",
            "GRYONIXNEXUS_FAST_MOUNTED",
        ).joinToString("\n")
        val projects = FastStorageMove.projects(probe)
        assertEquals(
            listOf(
                FastStorageMove.Project("/opt/immich", listOf("/opt/immich/postgres")),
                FastStorageMove.Project("/opt/nextcloud", listOf("/opt/nextcloud/db", "/opt/nextcloud/redis")),
            ),
            projects,
        )
        assertTrue(FastStorageMove.isMounted(probe))
        val move = FastStorageMove(FastStoragePlan.Target.Folder("/mnt/fast"), projects)
        assertEquals(fixture("fast-move.sh"), move.script())
        assertEquals(fixture("fast-restore.sh"), FastStorageRestore.script(projects))
        assertEquals(fixture("fast-cleanup.sh"), FastStorageRestore.cleanupScript(listOf("/opt/immich/postgres")))
        assertEquals(setOf("/opt/immich/postgres"), FastStorageMove.bound("x\nGRYONIXNEXUS_FAST_BOUND /opt/immich/postgres\n"))
    }

    @Test
    fun `smart reports each disk from real output`() {
        val health = DiskHealth.parse(fixture("smart-output.txt"))
        assertEquals(listOf("/dev/sda", "/dev/sdb", "/dev/sdc", "/dev/sdd"), health.map { it.path })
        assertEquals(DiskHealth.Verdict.GOOD, health[0].verdict)
        assertEquals(54, health[0].temperature)
        assertEquals(3550, health[0].powerOnHours)
        assertEquals(0, health[0].wornPercent)
        assertEquals(DiskHealth.Verdict.WATCH, health[1].verdict)
        assertEquals(10, health[1].badSectors)
        assertEquals(DiskHealth.Verdict.FAILING, health[2].verdict)
        assertEquals(DiskHealth.Verdict.UNKNOWN, health[3].verdict)
        assertEquals(fixture("smart.sh"), DiskHealth.script(listOf("/dev/sda", "/dev/sdb")))
    }

    @Test
    fun `a zfs resilver and scrub show their progress apart`() {
        val resilver = listOf(
            "  pool: tank", " state: DEGRADED",
            "  scan: resilver in progress since Thu Sep 25 10:00:00 2026",
            "        300G resilvered, 24.93% done, 02:30:00 to go",
            "config:", "  NAME STATE READ WRITE CKSUM", "  tank DEGRADED 0 0 0",
            "    mirror-0 DEGRADED 0 0 0", "      /dev/sda2 ONLINE 0 0 0",
            "errors: No known data errors",
        ).joinToString("\n")
        val pools = ZpoolReader.pools(resilver)
        assertEquals(StorageArray.State.Rebuilding(24.93), pools.first().state)
        assertEquals("mirror", pools.first().level)
        val scrub = resilver.replace("resilver in progress", "scrub in progress").replace("DEGRADED", "ONLINE")
        assertEquals(StorageArray.State.Checking(24.93), ZpoolReader.pools(scrub).first().state)
        val degradedScrub = resilver.replace("resilver in progress", "scrub in progress")
        assertEquals(StorageArray.State.Degraded, ZpoolReader.pools(degradedScrub).first().state)
    }

    @Test
    fun `speed scripts match the Swift golden and parse real output`() {
        assertEquals(fixture("speed-disk.sh"), SpeedTest.diskScript(SpeedTest.SYSTEM_DIRECTORY))
        assertEquals(fixture("speed-internet.sh"), SpeedTest.INTERNET_SCRIPT)
        val disk = requireNotNull(SpeedTest.parseDisk(fixture("speed-disk-output.txt")))
        assertEquals(268_435_456 / 0.438679, disk.writeBytesPerSecond, 1.0)
        assertFalse(disk.cached)
        val net = requireNotNull(SpeedTest.parseInternet(fixture("speed-internet-output.txt")))
        assertEquals(208_073_241.0 * 8, net.downloadBitsPerSecond, 1.0)
        assertEquals(null, SpeedTest.parseInternet("nocurl\n"))
        assertEquals(null, SpeedTest.parseInternet("down 22 403\nup 0 000\n"))
    }

    @Test
    fun `an earlier TrueNAS boot disk is free to format`() {
        val hardware = requireNotNull(ServerHardware.parse(fixture("probe-truenas-boot-pool.txt")))
        val pool = StorageArray.all(hardware).first { it.name == "boot-pool" }
        assertTrue(pool.isForeignSystemPool)
        assertEquals(listOf("/dev/sdb"), DiskFormatPlan.candidates(hardware).map { it.path })
    }

    @Test
    fun `swap script matches the golden and covers missing memory`() {
        assertEquals(fixture("swap-2g.sh"), SwapPlan(2).script())
        val gib = 1_073_741_824L
        assertEquals(2, SwapPlan.suggested(gib, 3 * gib))
        assertEquals(8, SwapPlan.suggested(gib, 30 * gib))
        val small = ServerHardware(1, 900 * 1_048_576L, "x86_64", 9 * gib, emptyList())
        val need = com.skaymer.gryonixnexus.catalog.ServerRequirements(2048, 2, false)
        assertEquals(HardwareVerdict.Level.DOES_NOT_FIT, HardwareVerdict.judge(small, need).level)
        val verdict = HardwareVerdict.judge(small.copy(swapBytes = 2 * gib), need)
        assertEquals(HardwareVerdict.Level.TIGHT, verdict.level)
        assertEquals(2 * gib, verdict.findings.first().swapBytes)
        assertEquals(
            HardwareVerdict.Level.FITS,
            HardwareVerdict.judge(small, com.skaymer.gryonixnexus.catalog.ServiceRegistry.relayRequirements).level,
        )
    }

    @Test
    fun `the probe reads swap`() {
        val output = "${ServerHardware.BEGIN_MARKER}\ncpu=1\nmem=918000000\nswap=2147479552\n${ServerHardware.END_MARKER}\n"
        assertEquals(2_147_479_552L, ServerHardware.parse(output)?.swapBytes)
    }
}
