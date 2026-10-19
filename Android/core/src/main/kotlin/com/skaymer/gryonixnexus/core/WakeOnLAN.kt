package com.skaymer.gryonixnexus.core

object WakeOnLAN {
    const val PORT = 9

    fun macBytes(text: String): ByteArray? {
        val digits = text.filter { it.isDigit() || it.lowercaseChar() in 'a'..'f' }
        val stripped = text.filterNot { it in ":-. " }
        if (digits.length != 12 || stripped.length != 12) return null
        return ByteArray(6) { index ->
            digits.substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }
    }

    /** `aa:bb:cc:dd:ee:ff` — the one shape a stored MAC is written in */
    fun normalised(text: String): String? =
        macBytes(text)?.joinToString(":") { "%02x".format(it) }

    fun magicPacket(mac: String): ByteArray? {
        val bytes = macBytes(mac) ?: return null
        val packet = ByteArray(6 + 16 * 6)
        for (index in 0 until 6) packet[index] = 0xFF.toByte()
        for (copy in 0 until 16) bytes.copyInto(packet, 6 + copy * 6)
        return packet
    }

    /** Reaches every machine on the sender's own network */
    const val LIMITED_BROADCAST = "255.255.255.255"

    /** Prints the default interface's MAC, then its broadcast address */
    const val READ_COMMAND =
        "dev=\$(ip route show default | awk '{print \$5; exit}'); cat /sys/class/net/\$dev/address; " +
            "ip -4 -o addr show dev \"\$dev\" | awk '{for(i=1;i<=NF;i++) if(\$i==\"brd\"){print \$(i+1); exit}}'"

    data class Read(val mac: String, val broadcast: String?)

    /** The MAC and broadcast address from [READ_COMMAND] */
    fun parseRead(output: String): Read? {
        val lines = output.lines().map { it.trim() }.filter { it.isNotEmpty() }
        val mac = lines.firstOrNull()?.let(::normalised) ?: return null
        return Read(mac, lines.getOrNull(1)?.takeIf { octets(it) != null })
    }

    /** Where to send: stored, from the address, or everywhere nearby */
    fun broadcast(stored: String?, host: String, resolved: String?): String {
        if (stored != null && octets(stored) != null) return stored
        return broadcastAddress(host) ?: resolved?.let(::broadcastAddress) ?: LIMITED_BROADCAST
    }

    /** The first IPv4 address a name resolves to */
    fun resolveIPv4(host: String): String? = try {
        java.net.InetAddress.getAllByName(host).firstOrNull { it is java.net.Inet4Address }?.hostAddress
    } catch (failure: Exception) {
        null
    }

    fun broadcastAddress(host: String): String? {
        val octets = octets(host) ?: return null
        return "${octets[0]}.${octets[1]}.${octets[2]}.255"
    }

    /** A private IPv4 address or an mDNS name */
    fun isLocalNetwork(host: String): Boolean {
        if (host.lowercase().endsWith(".local")) return true
        val octets = octets(host) ?: return false
        return when {
            octets[0] == 10 -> true
            octets[0] == 192 && octets[1] == 168 -> true
            octets[0] == 169 && octets[1] == 254 -> true
            octets[0] == 172 && octets[1] in 16..31 -> true
            else -> false
        }
    }

    fun command(mac: String, broadcast: String): String? {
        val bytes = macBytes(mac) ?: return null
        if (octets(broadcast) == null) return null
        val packet = ByteArray(6) { 0xFF.toByte() } + ByteArray(16 * 6) { bytes[it % 6] }
        val escaped = packet.joinToString("") { "\\x%02x".format(it) }
        val hex = packet.joinToString("") { "%02x".format(it) }
        val broadcastSend = "python3 -c 'import socket; s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); " +
            "s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1); " +
            "s.sendto(bytes.fromhex(\"$hex\"), (\"$broadcast\", $PORT))' 2>/dev/null"
        return "$broadcastSend || bash -c 'printf \"$escaped\" > /dev/udp/$broadcast/$PORT'"
    }

    /** One IPv4 address of this device with its prefix length */
    data class DeviceAddress(val address: String, val prefix: Int)

    /** Whether we share the machine's network, or null if unknown */
    fun sharesNetwork(device: List<DeviceAddress>, machine: String?, broadcast: String?): Boolean? {
        val subnets = device.mapNotNull { entry ->
            val address = number(entry.address) ?: return@mapNotNull null
            if (entry.prefix !in 0..32) return@mapNotNull null
            address to (if (entry.prefix == 0) 0L else (0xFFFFFFFFL shl (32 - entry.prefix)) and 0xFFFFFFFFL)
        }
        machine?.let(::number)?.let { target ->
            return subnets.any { (address, mask) -> (address and mask) == (target and mask) }
        }
        broadcast?.let(::number)?.takeIf { it != 0xFFFFFFFFL }?.let { target ->
            return subnets.any { (address, mask) -> (address and mask) == (target and mask) && mask != 0xFFFFFFFFL }
        }
        return null
    }

    private fun number(text: String): Long? =
        octets(text)?.fold(0L) { acc, octet -> (acc shl 8) or octet.toLong() }

    private fun octets(host: String): List<Int>? {
        val parts = host.split(".")
        if (parts.size != 4) return null
        return parts.map { part ->
            val value = part.toIntOrNull() ?: return null
            if (value !in 0..255 || value.toString() != part) return null
            value
        }
    }
}
