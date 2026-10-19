package com.skaymer.gryonixnexus.servercontrol

import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class PowerEstimateTest {
    private fun probe(vararg fields: String): PowerHardware =
        PowerHardware.parse((listOf(PowerHardware.BEGIN_MARKER) + fields + PowerHardware.END_MARKER).joinToString("\n"))!!

    private fun assertTotals(estimate: PowerEstimate, idle: Double, peak: Double) {
        assertEquals(idle, estimate.profile.idleWatts, 0.05)
        assertEquals(peak, estimate.profile.peakWatts, 0.05)
    }

    @Test
    fun `a kvm server counts a share of the host`() {
        val estimate = PowerEstimate.of(probe(
            "cpu= AMD EPYC-Milan Processor", "sockets=1", "cores= 6", "threads=12", "mem=25157267456",
            "board=Standard PC (i440FX + PIIX, 1996)", "chassis=1", "virt=kvm", "disks=vda:1:virtio ",
        ))
        assertTrue(estimate.isVirtual)
        assertEquals(listOf(PowerPart.Kind.VIRTUAL_SHARE, PowerPart.Kind.MEMORY), estimate.parts.map { it.kind })
        assertTotals(estimate, 25.9, 88.7)
    }

    @Test
    fun `a virtual machine is known by its board without systemd`() {
        assertTrue(probe("board=KVM", "threads=2").isVirtual)
        assertFalse(probe("board=Standard PC", "virt=none").isVirtual)
    }

    @Test
    fun `an n100 mini pc`() {
        val estimate = PowerEstimate.of(probe(
            "cpu= Intel(R) N100", "sockets=1", "cores= 4", "threads=4", "mem=17179869184",
            "board=Mini PC", "chassis=35", "virt=none", "disks=nvme0n1:0:nvme ", "gpus=0x8086 ",
        ))
        assertEquals(
            listOf(PowerPart.Kind.PROCESSOR, PowerPart.Kind.COMPACT_BOARD, PowerPart.Kind.MEMORY,
                PowerPart.Kind.NVME, PowerPart.Kind.POWER_SUPPLY),
            estimate.parts.map { it.kind },
        )
        assertEquals("Intel N100", estimate.parts.first().name)
        assertTotals(estimate, 9.8, 32.0)
    }

    @Test
    fun `a processor reading gets the rest of the machine added`() {
        val estimate = PowerEstimate.of(probe(
            "cpu= Intel(R) N100", "sockets=1", "cores= 4", "threads=4", "mem=17179869184",
            "board=Mini PC", "chassis=35", "virt=none", "disks=nvme0n1:0:nvme ", "gpus=0x8086 ",
        ))
        val unseen = 6.3 + 11.3 * 1.5 / 8.3
        assertEquals(unseen, estimate.unseenWatts("rapl", 5.0, 0.0), 1e-9)
        assertEquals(0.0, estimate.unseenWatts("ipmi", 40.0, 0.0), 1e-9)
        val reading = MetricsHistoryPoint(
            date = java.time.Instant.EPOCH, cpuPercent = 0.0, memUsedBytes = 1, memTotalBytes = 2,
            diskUsedBytes = 1, diskTotalBytes = 2, netReceivedPerSecond = null, netSentPerSecond = null,
            diskReadPerSecond = null, diskWrittenPerSecond = null, load1 = 0.0, temperatureCelsius = null,
            powerWatts = 5.0, powerSource = "rapl",
        )
        val once = EnergyMath.filled(listOf(reading), estimate.profile, estimate)
        assertEquals(5.0 + unseen, once[0].powerWatts!!, 1e-9)
        assertEquals("rapl+estimate", once[0].powerSource)
        assertEquals(once, EnergyMath.filled(once, estimate.profile, estimate))
    }

    @Test
    fun `a dual xeon rack server`() {
        val hardware = probe(
            "cpu= Intel(R) Xeon(R) CPU E5-2680 v4 @ 2.40GHz", "sockets=2", "cores= 14", "threads=56",
            "mem=137438953472", "board=PowerEdge R730", "chassis=23", "virt=none",
            "disks=sda:1:sata sdb:1:sata sdc:0:sata sr0:1:sata ", "gpus=0x102b ",
        )
        assertEquals(2, hardware.hdd)
        assertEquals(1, hardware.ssd)
        assertEquals(0, hardware.graphics)
        val estimate = PowerEstimate.of(hardware)
        assertEquals(2, estimate.parts.first().count)
        assertTrue(estimate.parts.any { it.kind == PowerPart.Kind.SERVER_BOARD })
        assertTotals(estimate, 104.6, 376.2)
    }

    @Test
    fun `a raspberry pi is one board plus its disk`() {
        val hardware = probe(
            "cpu=", "lscpu=  Cortex-A72", "sockets=0", "threads=4", "mem=3981262848",
            "board=Raspberry Pi 4 Model B Rev 1.4", "chassis=", "virt=none", "disks=mmcblk0:0: sda:0:usb ",
        )
        assertEquals("Cortex-A72", hardware.processor)
        val estimate = PowerEstimate.of(hardware)
        assertEquals(
            listOf(PowerPart.Kind.SINGLE_BOARD, PowerPart.Kind.SSD, PowerPart.Kind.POWER_SUPPLY),
            estimate.parts.map { it.kind },
        )
        assertTotals(estimate, 3.8, 11.1)
    }

    @Test
    fun `discrete graphics skip the amd processors own`() {
        assertEquals(1, probe("cpu=AMD Ryzen 5 5600G", "gpus=0x1002 0x10de ").graphics)
        assertEquals(1, probe("cpu=Intel Core i5-12400", "gpus=0x1002 ").graphics)
    }

    @Test
    fun `processor figures follow the model`() {
        val desktop = ProcessorPower.Platform.DESKTOP
        val compact = ProcessorPower.Platform.COMPACT
        val cases = listOf(
            listOf("AMD Ryzen 5 5600X 6-Core Processor", 6, 18.0, 105.0, desktop),
            listOf("Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz", 4, 2.0, 20.0, compact),
            listOf("Intel(R) Core(TM) i7-8700K CPU @ 3.70GHz", 6, 10.0, 150.0, desktop),
            listOf("Intel(R) Core(TM) i7-1165G7 @ 2.80GHz", 4, 3.0, 28.0, compact),
            listOf("Intel(R) Core(TM) i5-10400 CPU @ 2.90GHz", 6, 7.0, 70.0, desktop),
            listOf("Intel(R) Celeron(R) J4125 CPU @ 2.00GHz", 4, 2.0, 12.0, compact),
            listOf("AMD EPYC 7302 16-Core Processor", 16, 34.8, 160.0, ProcessorPower.Platform.SERVER),
            listOf("AMD EPYC 3151 4-Core Processor", 4, 10.0, 50.0, compact),
            listOf("Intel(R) Core(TM) Ultra 7 155H", 16, 4.0, 55.0, compact),
            listOf("Mystery CPU", 4, 6.0, 26.0, desktop),
        )
        for (case in cases) {
            val figures = ProcessorPower.figures(case[0] as String, case[1] as Int)
            assertEquals(case[2] as Double, figures.idle, 0.01, case[0] as String)
            assertEquals(case[3] as Double, figures.peak, 0.01, case[0] as String)
            assertEquals(case[4], figures.platform, case[0] as String)
        }
    }

    @Test
    fun `the estimate survives storage`() {
        val estimate = PowerEstimate.of(probe("cpu=Intel N100", "chassis=35"), epochSeconds = 100)
        val json = Json.encodeToString(PowerEstimate.serializer(), estimate)
        assertEquals(estimate, Json.decodeFromString(PowerEstimate.serializer(), json))
    }
}
