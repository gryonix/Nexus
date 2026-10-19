package com.skaymer.gryonixnexus.servercontrol

/** Parses `sysctl net.ipv4.ip_forward` output: "net.ipv4.ip_forward = 1" */
object SysctlParser {
    fun parseIPForwarding(output: String): Boolean {
        for (line in output.split("\n")) {
            val parts = line.split("=", limit = 2)
            if (parts.size != 2 || parts[0].trim() != "net.ipv4.ip_forward") continue
            when (parts[1].trim()) {
                "1" -> return true
                "0" -> return false
            }
        }
        throw ServerControlError.ParseFailure(
            "sysctl net.ipv4.ip_forward",
            "no 'net.ipv4.ip_forward = 0|1' line in output",
        )
    }
}

object PingParser {
    fun parse(output: String): PingResult {
        for (line in output.split("\n")) {
            if (!line.contains("transmitted")) continue
            val fields = line.split(",")
            if (fields.size < 2) continue
            val transmitted = leadingInt(fields[0]) ?: continue
            val received = leadingInt(fields[1]) ?: continue
            return PingResult(transmitted, received)
        }
        throw ServerControlError.ParseFailure(
            "ping",
            "no 'transmitted/received' statistics line in output",
        )
    }

    private fun leadingInt(field: String): Int? =
        field.trim().takeWhile { it.isDigit() }.toIntOrNull()
}

object DFParser {
    fun parse(output: String): List<DiskMount> {
        val lines = output.split("\n").filter { it.isNotEmpty() }
        if (lines.size <= 1) throw ServerControlError.ParseFailure("df", "empty output")

        val mounts = mutableListOf<DiskMount>()
        for (line in lines.drop(1)) {
            val fields = line.split(" ").filter { it.isNotEmpty() }
            if (fields.size < 4) continue
            val size = fields[fields.size - 3].toLongOrNull() ?: continue
            val used = fields[fields.size - 2].toLongOrNull() ?: continue
            val percent = fields.last().removeSuffix("%").toIntOrNull() ?: continue
            // Mount point may contain spaces: everything before the size field.
            val target = fields.subList(0, fields.size - 3).joinToString(" ")
            mounts += DiskMount(target, size, used, percent)
        }

        if (mounts.isEmpty()) throw ServerControlError.ParseFailure("df", "no parsable rows")
        return mounts
    }
}

object FreeParser {
    fun parse(output: String): MemoryUsage {
        var mem: Pair<Long, Long>? = null
        var swap: Pair<Long, Long>? = null

        for (line in output.split("\n")) {
            val fields = line.split(" ").filter { it.isNotEmpty() }
            if (fields.size < 3) continue
            val total = fields[1].toLongOrNull() ?: continue
            val used = fields[2].toLongOrNull() ?: continue
            when (fields[0]) {
                "Mem:" -> mem = total to used
                "Swap:" -> swap = total to used
            }
        }

        val memory = mem ?: throw ServerControlError.ParseFailure("free -b", "no 'Mem:' row")
        return MemoryUsage(
            memTotalBytes = memory.first,
            memUsedBytes = memory.second,
            swapTotalBytes = swap?.first ?: 0,
            swapUsedBytes = swap?.second ?: 0,
        )
    }
}

object WGShowParser {
    private class PeerBuilder(val publicKey: String) {
        var endpoint: String? = null
        var latestHandshake: String? = null
        var transfer: String? = null
        var allowedIPs: List<String> = emptyList()

        fun build() = WGPeer(publicKey, endpoint, latestHandshake, transfer, allowedIPs)
    }

    fun parse(output: String): WGStatus {
        var interfaceName: String? = null
        var interfacePublicKey: String? = null
        var listeningPort: Int? = null
        val peers = mutableListOf<PeerBuilder>()

        for (rawLine in output.split("\n")) {
            val line = rawLine.trim()
            val colon = line.indexOf(':')
            if (colon < 0) continue
            val key = line.substring(0, colon).trim().lowercase()
            val value = line.substring(colon + 1).trim()

            when (key) {
                "interface" -> interfaceName = value
                "peer" -> peers += PeerBuilder(value)
                "public key" -> if (peers.isEmpty()) interfacePublicKey = value
                "listening port" -> if (peers.isEmpty()) listeningPort = value.toIntOrNull()
                "endpoint" -> peers.lastOrNull()?.endpoint = value
                "latest handshake" -> peers.lastOrNull()?.latestHandshake = value
                "transfer" -> peers.lastOrNull()?.transfer = value
                "allowed ips" -> peers.lastOrNull()?.allowedIPs =
                    value.split(",").map { it.trim() }
            }
        }

        val name = interfaceName
            ?: throw ServerControlError.ParseFailure("wg show", "no 'interface:' block in output")
        return WGStatus(
            WGInterfaceStatus(name, interfacePublicKey, listeningPort),
            peers.map { it.build() },
        )
    }
}
