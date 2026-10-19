package com.skaymer.gryonixnexus.catalog.storage

/** A swap file, made once and kept across restarts */
data class SwapPlan(val sizeGB: Int) {
    fun script(): String = listOf(
        "#!/bin/bash",
        "set -euo pipefail",
        "FILE=$PATH",
        "SIZE_MB=${sizeGB * 1024}",
        "if swapon --show=NAME --noheadings | grep -qx \"\$FILE\"; then swapoff \"\$FILE\"; fi",
        "rm -f \"\$FILE\"",
        "FREE_MB=\$(( \$(df -B1 --output=avail / | tail -n 1 | tr -d ' ') / 1048576 ))",
        "if [ \"\$SIZE_MB\" -ge \"\$FREE_MB\" ]; then echo \"not enough disk: \$((FREE_MB / 1024)) GB free\" >&2; exit 3; fi",
        "fallocate -l \"\${SIZE_MB}M\" \"\$FILE\" 2>/dev/null || dd if=/dev/zero of=\"\$FILE\" bs=1M count=\"\$SIZE_MB\" status=none",
        "chmod 600 \"\$FILE\"",
        "mkswap \"\$FILE\" >/dev/null",
        "swapon \"\$FILE\"",
        "grep -q \"^\$FILE \" /etc/fstab || echo \"\$FILE none swap sw 0 0\" >> /etc/fstab",
        "echo $DONE_MARKER",
    ).joinToString("\n") + "\n"

    companion object {
        const val DONE_MARKER = "GRYONIXNEXUS_SWAP_DONE"
        const val PATH = "/swapfile-gryonixnexus"

        /** Sizes the app offers */
        val SIZES = listOf(1, 2, 4, 8)

        /** Sizes a custom value may take */
        val ALLOWED = 1..256

        /** The smallest offered size that covers the missing memory */
        fun suggested(memoryBytes: Long, needBytes: Long): Int {
            val missing = (needBytes - memoryBytes).coerceAtLeast(0) / 1_073_741_824.0
            return SIZES.firstOrNull { it >= missing } ?: SIZES.last()
        }
    }
}
