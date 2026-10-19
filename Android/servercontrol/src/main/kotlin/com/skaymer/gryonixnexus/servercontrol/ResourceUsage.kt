package com.skaymer.gryonixnexus.servercontrol

/** One mounted filesystem from `df -B1` */
data class DiskMount(
    val target: String,
    val sizeBytes: Long,
    val usedBytes: Long,
    val usedPercent: Int,
) {
    /** 0..1 for progress-bar style indicators */
    val usedFraction: Double
        get() = if (sizeBytes > 0) usedBytes.toDouble() / sizeBytes.toDouble() else 0.0
}

/** Mem:/Swap: rows of `free -b` */
data class MemoryUsage(
    val memTotalBytes: Long,
    val memUsedBytes: Long,
    val swapTotalBytes: Long,
    val swapUsedBytes: Long,
) {
    val memUsedFraction: Double
        get() = if (memTotalBytes > 0) memUsedBytes.toDouble() / memTotalBytes.toDouble() else 0.0

    val swapUsedFraction: Double
        get() = if (swapTotalBytes > 0) swapUsedBytes.toDouble() / swapTotalBytes.toDouble() else 0.0
}

/** Result of a ping probe: packets received out of transmitted */
data class PingResult(val transmitted: Int, val received: Int) {
    val isAlive: Boolean get() = received > 0
}

data class GeneralVPSStatus(
    val forwarding: Boolean,
    val selfPing: PingResult,
    val tunnelPing: PingResult,
)
