package com.skaymer.gryonixnexus.servercontrol

data class WGStatus(
    val `interface`: WGInterfaceStatus,
    val peers: List<WGPeer>,
)

data class WGInterfaceStatus(
    val name: String,
    val publicKey: String?,
    val listeningPort: Int?,
)

data class WGPeer(
    val publicKey: String,
    val endpoint: String?,
    /** Verbatim human text from wg, e.g */
    val latestHandshake: String?,
    /** Verbatim transfer line, e.g */
    val transfer: String?,
    val allowedIPs: List<String>,
) {
    val freshness: HealthLevel
        get() {
            val handshake = latestHandshake?.lowercase()
            if (handshake.isNullOrEmpty() || handshake.contains("never")) return HealthLevel.CRITICAL
            val staleUnits = listOf("hour", "day", "week", "month", "year")
            if (staleUnits.any { handshake.contains(it) }) return HealthLevel.WARNING
            if (handshake.contains("second") || handshake.contains("minute")) return HealthLevel.OK
            return HealthLevel.WARNING
        }
}
