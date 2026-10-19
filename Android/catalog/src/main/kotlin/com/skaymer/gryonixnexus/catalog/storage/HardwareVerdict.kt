package com.skaymer.gryonixnexus.catalog.storage

import com.skaymer.gryonixnexus.catalog.ServerRequirements

/** Whether a server can carry the chosen services */
data class HardwareVerdict(val findings: List<Finding>) {
    enum class Level { FITS, TIGHT, DOES_NOT_FIT }

    enum class Resource { MEMORY, DISK }

    data class Finding(
        val resource: Resource,
        val level: Level,
        val haveBytes: Long,
        val needBytes: Long,
        /** Swap counted toward memory, zero otherwise */
        val swapBytes: Long = 0,
    )

    val level: Level get() = findings.maxOfOrNull { it.level } ?: Level.FITS

    companion object {
        /** Headroom below which a fit reads as tight */
        private const val COMFORT = 1.25
        private const val MEBIBYTE = 1_048_576L
        private const val GIBIBYTE = 1_073_741_824L

        fun judge(hardware: ServerHardware, requirements: ServerRequirements) = HardwareVerdict(
            listOf(
                memory(hardware, requirements.memoryMB * MEBIBYTE),
                finding(Resource.DISK, hardware.rootFreeBytes, requirements.diskGB * GIBIBYTE),
            ),
        )

        /** Too little memory is only tight when swap covers it */
        private fun memory(hardware: ServerHardware, need: Long): Finding {
            val found = finding(Resource.MEMORY, hardware.memoryBytes, need)
            if (found.level != Level.DOES_NOT_FIT || hardware.swapBytes <= 0) return found
            val covered = hardware.memoryBytes + hardware.swapBytes >= need
            return found.copy(level = if (covered) Level.TIGHT else found.level, swapBytes = hardware.swapBytes)
        }

        private fun finding(resource: Resource, have: Long, need: Long): Finding {
            val level = when {
                have < need -> Level.DOES_NOT_FIT
                have.toDouble() < need.toDouble() * COMFORT -> Level.TIGHT
                else -> Level.FITS
            }
            return Finding(resource, level, have, need)
        }
    }
}
