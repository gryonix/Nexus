package com.skaymer.gryonixnexus.servercontrol

import kotlin.math.roundToLong
import kotlinx.serialization.Serializable

/** One line of the estimate: a part and its watts */
@Serializable
data class PowerPart(
    val kind: Kind,
    val name: String = "",
    val count: Int = 1,
    val idleWatts: Double,
    val peakWatts: Double,
) {
    @Serializable
    enum class Kind {
        PROCESSOR, MEMORY, NVME, SSD, HDD, GRAPHICS,
        SERVER_BOARD, DESKTOP_BOARD, COMPACT_BOARD, SINGLE_BOARD, VIRTUAL_SHARE, POWER_SUPPLY,
    }

    companion object {
        fun of(kind: Kind, name: String = "", count: Int = 1, idle: Double, peak: Double) =
            PowerPart(kind, name, count, tenths(idle), tenths(peak))

        private fun tenths(value: Double) = (value * 10).roundToLong() / 10.0
    }
}

/** Watts a machine likely draws, added up from its parts */
@Serializable
data class PowerEstimate(
    val parts: List<PowerPart>,
    val isVirtual: Boolean,
    val detectedAtEpochSeconds: Long,
) {
    val profile: EnergyProfile
        get() = EnergyProfile(parts.sumOf { it.idleWatts }, parts.sumOf { it.peakWatts })

    /** Watts of the parts a partial sensor does not see */
    fun unseenWatts(source: String, measured: Double, cpuPercent: Double?): Double {
        val covered = covered(source) ?: return 0.0
        val load = (cpuPercent ?: 0.0).coerceIn(0.0, 100.0) / 100
        val own = parts.filter { it.kind != PowerPart.Kind.POWER_SUPPLY }
        val others = own.filter { it.kind !in covered }
            .sumOf { it.idleWatts + (it.peakWatts - it.idleWatts) * load }
        val ownIdle = own.sumOf { it.idleWatts }
        val supplyIdle = parts.firstOrNull { it.kind == PowerPart.Kind.POWER_SUPPLY }?.idleWatts ?: 0.0
        val losses = if (ownIdle > 0) supplyIdle / ownIdle else 0.0
        return others + (measured + others) * losses
    }

    companion object {
        /** Part kinds a partial sensor already measures */
        fun covered(source: String): Set<PowerPart.Kind>? = when (source) {
            "rapl", "hwmon" -> setOf(PowerPart.Kind.PROCESSOR, PowerPart.Kind.VIRTUAL_SHARE)
            "pi" -> setOf(PowerPart.Kind.SINGLE_BOARD)
            else -> null
        }

        private val SERVER_CHASSIS = setOf(17, 23, 25, 28, 29)
        private val COMPACT_CHASSIS = setOf(8, 9, 10, 13, 14, 30, 31, 32, 35, 36)

        fun of(hardware: PowerHardware, epochSeconds: Long = System.currentTimeMillis() / 1_000): PowerEstimate {
            val board = SingleBoard.figures(hardware)
            val parts = when {
                hardware.isVirtual -> virtualParts(hardware)
                board != null -> (listOf(board) + diskParts(hardware)).let { it + losses(it, 0.85) }
                else -> machineParts(hardware)
            }
            return PowerEstimate(parts, hardware.isVirtual, epochSeconds)
        }

        private fun virtualParts(hardware: PowerHardware): List<PowerPart> {
            val threads = maxOf(hardware.threads, 1)
            return listOf(
                PowerPart.of(PowerPart.Kind.VIRTUAL_SHARE, count = threads, idle = 2.0 * threads, peak = 7.0 * threads),
                memory(hardware.memoryBytes),
            )
        }

        private fun machineParts(hardware: PowerHardware): List<PowerPart> {
            val cpu = ProcessorPower.figures(hardware.processor, hardware.coresPerSocket)
            val sockets = hardware.sockets.toDouble()
            val platform = platform(hardware, cpu.platform)
            val parts = mutableListOf(
                PowerPart.of(PowerPart.Kind.PROCESSOR, ProcessorPower.normalized(hardware.processor), hardware.sockets,
                    idle = cpu.idle * sockets, peak = cpu.peak * sockets),
                board(platform, hardware.sockets),
                memory(hardware.memoryBytes),
            )
            parts += diskParts(hardware)
            if (hardware.graphics > 0) {
                val cards = hardware.graphics.toDouble()
                parts += PowerPart.of(PowerPart.Kind.GRAPHICS, count = hardware.graphics, idle = 12 * cards, peak = 15 * cards)
            }
            val efficiency = when (platform) {
                ProcessorPower.Platform.SERVER -> 0.9
                ProcessorPower.Platform.DESKTOP -> 0.87
                ProcessorPower.Platform.COMPACT -> 0.85
            }
            return parts + losses(parts, efficiency)
        }

        private fun platform(hardware: PowerHardware, cpu: ProcessorPower.Platform) = when {
            hardware.chassis in SERVER_CHASSIS || hardware.sockets > 1 -> ProcessorPower.Platform.SERVER
            hardware.chassis in COMPACT_CHASSIS -> ProcessorPower.Platform.COMPACT
            else -> cpu
        }

        private fun board(platform: ProcessorPower.Platform, sockets: Int): PowerPart = when (platform) {
            ProcessorPower.Platform.SERVER -> {
                val idle = 30 + 15.0 * (sockets - 1)
                PowerPart.of(PowerPart.Kind.SERVER_BOARD, idle = idle, peak = idle + 25)
            }
            ProcessorPower.Platform.DESKTOP -> PowerPart.of(PowerPart.Kind.DESKTOP_BOARD, idle = 10.0, peak = 15.0)
            ProcessorPower.Platform.COMPACT -> PowerPart.of(PowerPart.Kind.COMPACT_BOARD, idle = 3.0, peak = 6.0)
        }

        private fun memory(bytes: Long): PowerPart {
            val gigabytes = bytes / 1_073_741_824.0
            return PowerPart.of(PowerPart.Kind.MEMORY, count = Math.round(gigabytes).toInt(),
                idle = maxOf(0.08 * gigabytes, 1.0), peak = maxOf(0.2 * gigabytes, 1.5))
        }

        private fun diskParts(hardware: PowerHardware): List<PowerPart> = listOf(
            Triple(PowerPart.Kind.NVME, hardware.nvme, 2.0 to 6.0),
            Triple(PowerPart.Kind.SSD, hardware.ssd, 0.5 to 3.0),
            Triple(PowerPart.Kind.HDD, hardware.hdd, 5.0 to 8.0),
        ).filter { it.second > 0 }.map { (kind, count, watts) ->
            PowerPart.of(kind, count = count, idle = watts.first * count, peak = watts.second * count)
        }

        /** Watts the power supply turns into heat */
        private fun losses(parts: List<PowerPart>, efficiency: Double): PowerPart {
            val extra = 1 / efficiency - 1
            return PowerPart.of(PowerPart.Kind.POWER_SUPPLY,
                idle = parts.sumOf { it.idleWatts } * extra, peak = parts.sumOf { it.peakWatts } * extra)
        }
    }
}

/** Whole-board watts for single-board computers */
internal object SingleBoard {
    private val boards = listOf(
        Triple("Raspberry Pi 5", 2.7, 7.5),
        Triple("Raspberry Pi Compute Module 4", 2.0, 5.5),
        Triple("Raspberry Pi (4|400)", 2.7, 6.4),
        Triple("Raspberry Pi 3", 1.9, 5.1),
        Triple("Raspberry Pi Zero 2", 0.6, 3.0),
        Triple("Raspberry Pi Zero", 0.5, 1.2),
        Triple("Raspberry Pi", 1.4, 3.5),
    ).map { (pattern, idle, peak) -> Triple(Regex(pattern, RegexOption.IGNORE_CASE), idle, peak) }
    private val ARM = Regex("Cortex|ARMv", RegexOption.IGNORE_CASE)

    fun figures(hardware: PowerHardware): PowerPart? {
        boards.firstOrNull { it.first.containsMatchIn(hardware.board) }?.let { (_, idle, peak) ->
            return PowerPart.of(PowerPart.Kind.SINGLE_BOARD, hardware.board, idle = idle, peak = peak)
        }
        val armBoard = hardware.chassis == 0 && hardware.board.isNotEmpty() && ARM.containsMatchIn(hardware.processor)
        return if (armBoard) PowerPart.of(PowerPart.Kind.SINGLE_BOARD, hardware.board, idle = 2.5, peak = 8.0) else null
    }
}
