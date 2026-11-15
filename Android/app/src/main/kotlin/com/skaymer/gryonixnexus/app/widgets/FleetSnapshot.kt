package com.skaymer.gryonixnexus.app.widgets

import kotlinx.serialization.Serializable

/** Every server's last readings and the tunnel, for widgets */
@Serializable
data class FleetSnapshot(
    val generatedAt: Long = System.currentTimeMillis(),
    val servers: List<Server> = emptyList(),
    val tunnel: TunnelSnapshot = TunnelSnapshot(),
) {
    @Serializable
    data class Server(
        val id: String,
        val name: String,
        val protocols: List<ProtocolDevices> = emptyList(),
        val failure: String? = null,
        val metrics: Reading? = null,
        val services: ServicesSummary? = null,
        val security: SecuritySummary? = null,
        val backups: BackupsSummary? = null,
        val updates: UpdatesSummary? = null,
    ) {
        val deviceCount: Int get() = protocols.sumOf { it.deviceCount }

        val hasAnyReading: Boolean
            get() = metrics != null || services != null || security != null ||
                backups != null || updates != null || protocols.isNotEmpty()
    }

    @Serializable
    data class Reading(
        val cpuPercent: Double? = null,
        val memUsedBytes: Long = 0,
        val memTotalBytes: Long = 0,
        val diskUsedBytes: Long = 0,
        val diskTotalBytes: Long = 0,
        val machineLabel: String = "",
        val takenAt: Long,
    ) {
        val memoryPercent: Double? get() = if (memTotalBytes > 0) memUsedBytes * 100.0 / memTotalBytes else null
        val diskPercent: Double? get() = if (diskTotalBytes > 0) diskUsedBytes * 100.0 / diskTotalBytes else null
    }

    @Serializable
    data class ServicesSummary(val total: Int, val needingAttention: Int, val takenAt: Long)

    @Serializable
    data class SecuritySummary(
        val isPresent: Boolean,
        val engineRunning: Boolean,
        val bouncerRunning: Boolean,
        val alertsLast24h: Int,
        val localBans: Int,
        val communityBlocklistIPs: Int,
        val takenAt: Long,
    ) {
        val isGuarding: Boolean get() = isPresent && engineRunning && bouncerRunning
    }

    @Serializable
    data class BackupsSummary(
        val isOn: Boolean,
        val everyHours: Int? = null,
        val everyDays: Int? = null,
        val servicesCovered: Int,
        val retention: Int,
        val takenAt: Long,
    )

    @Serializable
    data class UpdatesSummary(val waiting: Int, val checked: Int, val lastRunOnServer: Long? = null, val takenAt: Long)

    @Serializable
    data class ProtocolDevices(val protocolID: String, val deviceCount: Int, val deviceNames: List<String> = emptyList())

    val deviceCount: Int get() = servers.sumOf { it.deviceCount }

    val serversWithServiceReadings: List<Server> get() = servers.filter { it.services != null }

    val totalServices: Int get() = serversWithServiceReadings.sumOf { it.services?.total ?: 0 }

    val servicesNeedingAttention: Int get() = serversWithServiceReadings.sumOf { it.services?.needingAttention ?: 0 }

    val unreachableServerCount: Int get() = servers.count { it.failure != null }

    /** The stalest server's newest reading time */
    val oldestReadingAt: Long?
        get() = servers.mapNotNull { server ->
            listOfNotNull(server.metrics?.takenAt, server.services?.takenAt, server.security?.takenAt,
                server.backups?.takenAt, server.updates?.takenAt).maxOrNull()
        }.minOrNull()
}

/** This device's tunnel, as the widgets show it */
@Serializable
data class TunnelSnapshot(
    val state: State = State.OFF,
    val since: Long? = null,
    val profileName: String? = null,
    val serverName: String? = null,
    val protocolName: String? = null,
    val profileCount: Int = 0,
) {
    enum class State { OFF, CONNECTING, CONNECTED, FAILED }

    val isActive: Boolean get() = state == State.CONNECTED

    val subtitle: String? get() = listOfNotNull(serverName, protocolName).joinToString(" · ").ifEmpty { null }
}
