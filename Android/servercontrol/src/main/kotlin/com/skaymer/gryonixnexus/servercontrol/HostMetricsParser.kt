package com.skaymer.gryonixnexus.servercontrol

/** Parses the combined `CommandCatalog.HOST_METRICS` probe output into one [HostMetricsSample] */
object HostMetricsParser {
    fun parse(output: String): HostMetricsSample {
        val sections = splitSections(output)
        val sample = HostMetricsSample()

        val stat = sections["STAT"]
        val mem = sections["MEM"]
        val uptime = sections["UPTIME"]
        val usable = stat != null && parseStat(stat, sample) &&
            mem != null && parseMeminfo(mem, sample) &&
            uptime != null && parseUptime(uptime, sample)
        if (!usable) {
            throw ServerControlError.ParseFailure("hostMetrics", "missing cpu/mem/uptime sections")
        }

        sections["LOAD"]?.let { parseLoadavg(it, sample) }
        sections["NET"]?.let { parseNetDev(it, sample) }
        sections["DISKSTATS"]?.let { parseDiskstats(it, sample) }
        sections["DF"]?.let { sample.mounts = runCatching { DFParser.parse(it) }.getOrDefault(emptyList()) }
        sections["OS"]?.let { parseOSRelease(it, sample) }
        sections["NPROC"]?.let {
            if (sample.cpuCores == 0) sample.cpuCores = it.trim().toIntOrNull() ?: 0
        }
        sections["TEMP"]?.let { parseTemperatures(it, sample) }

        return sample
    }

    // ------------------------------------------------------------- Sections

    private fun splitSections(output: String): Map<String, String> {
        val sections = mutableMapOf<String, String>()
        var currentName: String? = null
        var currentBody = mutableListOf<String>()
        for (line in output.split("\n")) {
            val trimmed = line.trim()
            if (trimmed.startsWith("@@") && trimmed.endsWith("@@") && trimmed.length > 4) {
                currentName?.let { sections[it] = currentBody.joinToString("\n") }
                currentName = trimmed.substring(2, trimmed.length - 2)
                currentBody = mutableListOf()
            } else {
                currentBody += line
            }
        }
        currentName?.let { sections[it] = currentBody.joinToString("\n") }
        return sections
    }

    // ----------------------------------------------------------- /proc/stat

    private fun parseStat(body: String, sample: HostMetricsSample): Boolean {
        var cores = 0
        var parsedAggregate = false
        for (line in body.split("\n")) {
            val fields = line.split(" ").filter { it.isNotEmpty() }
            val first = fields.firstOrNull() ?: continue
            if (first == "cpu") {
                // user nice system idle iowait irq softirq steal
                val ticks = fields.drop(1).take(8).mapNotNull { it.toLongOrNull() }
                if (ticks.size < 4) continue
                sample.cpuTotalTicks = ticks.sum()
                sample.cpuIdleTicks = ticks[3] + (if (ticks.size > 4) ticks[4] else 0)
                parsedAggregate = true
            } else if (first.startsWith("cpu")) {
                cores += 1
            }
        }
        if (cores > 0) sample.cpuCores = cores
        return parsedAggregate
    }

    // -------------------------------------------------------- /proc/meminfo

    private fun parseMeminfo(body: String, sample: HostMetricsSample): Boolean {
        val values = mutableMapOf<String, Long>()
        for (line in body.split("\n")) {
            val parts = line.split(":", limit = 2)
            if (parts.size != 2) continue
            val number = parts[1].split(" ").firstOrNull { it.isNotEmpty() } ?: continue
            val kb = number.toLongOrNull() ?: continue
            values[parts[0]] = kb * 1024
        }
        val total = values["MemTotal"] ?: return false
        val available = values["MemAvailable"]
            ?: ((values["MemFree"] ?: 0) + (values["Buffers"] ?: 0) + (values["Cached"] ?: 0))
        sample.memTotalBytes = total
        sample.memUsedBytes = maxOf(0, total - available)
        val swapTotal = values["SwapTotal"] ?: 0
        sample.swapTotalBytes = swapTotal
        sample.swapUsedBytes = maxOf(0, swapTotal - (values["SwapFree"] ?: 0))
        return true
    }

    // --------------------------------------------- /proc/uptime, /proc/loadavg

    private fun parseUptime(body: String, sample: HostMetricsSample): Boolean {
        val first = body.split(" ").firstOrNull { it.isNotEmpty() } ?: return false
        val seconds = first.trim().toDoubleOrNull() ?: return false
        sample.uptimeSeconds = seconds
        return true
    }

    private fun parseLoadavg(body: String, sample: HostMetricsSample) {
        val fields = body.split(" ").filter { it.isNotEmpty() }
        if (fields.size < 3) return
        sample.load1 = fields[0].toDoubleOrNull() ?: 0.0
        sample.load5 = fields[1].toDoubleOrNull() ?: 0.0
        sample.load15 = fields[2].toDoubleOrNull() ?: 0.0
    }

    // -------------------------------------------------------- /proc/net/dev

    private val virtualPrefixes = listOf(
        "veth", "docker", "br-", "virbr", "wg", "awg", "tun", "tap", "tailscale", "zt", "cali",
        "flannel", "cni", "ifb", "dummy",
    )

    /** Interfaces whose bytes also pass a real one */
    internal fun isVirtualInterface(name: String): Boolean =
        name == "lo" || virtualPrefixes.any { name.startsWith(it) }

    private fun parseNetDev(body: String, sample: HostMetricsSample) {
        var received = 0L
        var sent = 0L
        for (line in body.split("\n")) {
            val parts = line.split(":", limit = 2)
            if (parts.size != 2) continue // header lines have no colon
            val name = parts[0].trim()
            if (isVirtualInterface(name)) continue
            val fields = parts[1].split(" ").filter { it.isNotEmpty() }
            if (fields.size < 9) continue
            val rx = fields[0].toLongOrNull() ?: continue
            val tx = fields[8].toLongOrNull() ?: continue
            received += rx
            sent += tx
        }
        sample.netReceivedBytes = received
        sample.netSentBytes = sent
    }

    // ------------------------------------------------------ /proc/diskstats

    /** Whole physical/virtual disks only — partitions would double-count */
    private val WHOLE_DISK =
        Regex("^(sd[a-z]+|vd[a-z]+|xvd[a-z]+|hd[a-z]+|nvme\\d+n\\d+|mmcblk\\d+)$")

    private fun parseDiskstats(body: String, sample: HostMetricsSample) {
        var readBytes = 0L
        var writtenBytes = 0L
        for (line in body.split("\n")) {
            val fields = line.split(" ").filter { it.isNotEmpty() }
            // major minor name reads rmerged rsectors rms writes wmerged wsectors ...
            if (fields.size < 10) continue
            if (!WHOLE_DISK.matches(fields[2])) continue
            val readSectors = fields[5].toLongOrNull() ?: continue
            val writtenSectors = fields[9].toLongOrNull() ?: continue
            // /proc/diskstats sector counts are always in 512-byte units.
            readBytes += readSectors * 512
            writtenBytes += writtenSectors * 512
        }
        sample.diskReadBytes = readBytes
        sample.diskWrittenBytes = writtenBytes
    }

    // ------------------------------------------ /etc/os-release, thermal zones

    private fun parseOSRelease(body: String, sample: HostMetricsSample) {
        for (line in body.split("\n")) {
            val parts = line.split("=", limit = 2)
            if (parts.size != 2) continue
            val value = parts[1].trim('"')
            when (parts[0]) {
                "ID" -> sample.osID = value
                "PRETTY_NAME" -> sample.osPrettyName = value
            }
        }
    }

    private fun parseTemperatures(body: String, sample: HostMetricsSample) {
        sample.temperatureCelsius = body.split("\n")
            .mapNotNull { it.trim().toDoubleOrNull() }
            .map { it / 1000 } // millidegrees
            .filter { it > 0 && it < 150 }
            .maxOrNull()
    }
}
