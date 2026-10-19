package com.skaymer.gryonixnexus.servercontrol

/** The parts of a machine that decide its power draw */
data class PowerHardware(
    val processor: String = "",
    val sockets: Int = 1,
    val coresPerSocket: Int = 0,
    val threads: Int = 0,
    val memoryBytes: Long = 0,
    val board: String = "",
    /** SMBIOS chassis type number, 0 when unknown */
    val chassis: Int = 0,
    val virtualization: String = "",
    val nvme: Int = 0,
    val ssd: Int = 0,
    val hdd: Int = 0,
    val graphics: Int = 0,
) {
    val isVirtual: Boolean
        get() = if (virtualization.isNotEmpty()) virtualization != "none"
        else VIRTUAL_BOARDS.containsMatchIn(board)

    companion object {
        const val BEGIN_MARKER = "GRYONIXNEXUS_POWER_BEGIN"
        const val END_MARKER = "GRYONIXNEXUS_POWER_END"
        private val VIRTUAL_BOARDS =
            Regex("KVM|QEMU|VMware|VirtualBox|HVM domU|Virtual Machine|Standard PC \\(", RegexOption.IGNORE_CASE)
        private val SKIPPED_DISKS = listOf("loop", "zram", "ram", "sr", "fd", "md", "dm-", "nbd", "mmcblk")

        /** Read-only probe; prints key=value lines between markers */
        val PROBE_COMMAND = listOf(
            "echo $BEGIN_MARKER",
            "echo \"cpu=\$(grep -m1 '^model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2-)\"",
            "echo \"lscpu=\$(LC_ALL=C lscpu 2>/dev/null | awk -F: '/^Model name/ {print \$2; exit}')\"",
            "echo \"sockets=\$(grep '^physical id' /proc/cpuinfo 2>/dev/null | sort -u | wc -l)\"",
            "echo \"cores=\$(grep -m1 '^cpu cores' /proc/cpuinfo 2>/dev/null | cut -d: -f2)\"",
            "echo \"threads=\$(nproc 2>/dev/null)\"",
            "echo \"mem=\$(awk '/^MemTotal:/ {printf \"%.0f\", \$2 * 1024}' /proc/meminfo 2>/dev/null)\"",
            "echo \"board=\$({ cat /proc/device-tree/model || cat /sys/class/dmi/id/product_name; } 2>/dev/null | tr -d '\\000')\"",
            "echo \"chassis=\$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)\"",
            "echo \"virt=\$(systemd-detect-virt 2>/dev/null)\"",
            "echo \"disks=\$(lsblk -dn -o NAME,ROTA,TRAN 2>/dev/null | awk '{print \$1\":\"\$2\":\"\$3}' | tr '\\n' ' ')\"",
            "echo \"gpus=\$(cat /sys/class/drm/card[0-9]*/device/vendor 2>/dev/null | tr '\\n' ' ')\"",
            "echo $END_MARKER",
        ).joinToString("; ")

        fun parse(output: String): PowerHardware? {
            val begin = output.indexOf(BEGIN_MARKER).takeIf { it >= 0 } ?: return null
            val end = output.indexOf(END_MARKER, begin + BEGIN_MARKER.length).takeIf { it >= 0 } ?: return null
            val fields = output.substring(begin + BEGIN_MARKER.length, end).split("\n")
                .mapNotNull { line ->
                    val equals = line.indexOf('=')
                    if (equals < 0) null else line.substring(0, equals) to line.substring(equals + 1).trim()
                }.toMap()
            return make(fields)
        }

        private fun make(fields: Map<String, String>): PowerHardware {
            fun number(key: String) = fields[key]?.toIntOrNull() ?: 0
            val cpu = fields["cpu"].orEmpty()
            val processor = cpu.ifEmpty { fields["lscpu"].orEmpty() }
            val sockets = maxOf(number("sockets"), 1)
            val threads = number("threads")
            val disks = countDisks(fields["disks"].orEmpty())
            return PowerHardware(
                processor = processor,
                sockets = sockets,
                coresPerSocket = if (number("cores") > 0) number("cores") else maxOf(threads / sockets, 1),
                threads = threads,
                memoryBytes = fields["mem"]?.toLongOrNull() ?: 0,
                board = fields["board"].orEmpty(),
                chassis = number("chassis"),
                virtualization = fields["virt"].orEmpty(),
                nvme = disks[0], ssd = disks[1], hdd = disks[2],
                graphics = countGraphics(fields["gpus"].orEmpty(), processor),
            )
        }

        /** NVMe, SATA SSD and spinning disk counts */
        private fun countDisks(text: String): IntArray {
            val counts = IntArray(3)
            for (entry in text.split(" ").filter { it.isNotEmpty() }) {
                val parts = entry.split(":")
                val name = parts.first()
                if (SKIPPED_DISKS.any { name.startsWith(it) }) continue
                val transport = parts.getOrElse(2) { "" }
                when {
                    transport == "nvme" || name.startsWith("nvme") -> counts[0]++
                    parts.getOrNull(1) == "1" -> counts[2]++
                    else -> counts[1]++
                }
            }
            return counts
        }

        /** Add-in cards; AMD graphics on AMD processors are integrated */
        private fun countGraphics(text: String, processor: String): Int {
            val onAMD = processor.contains("AMD", ignoreCase = true)
            return text.split(" ").count { it == "0x10de" || (it == "0x1002" && !onAMD) }
        }
    }
}
