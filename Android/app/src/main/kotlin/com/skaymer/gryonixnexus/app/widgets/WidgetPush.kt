package com.skaymer.gryonixnexus.app.widgets

import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.notify.RelayServers
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** A server's quiet summary, turned into widget readings */
object WidgetPush {
    const val KIND = "gnx.widgets"

    fun received(app: GryonixApplication, data: JsonObject) {
        val serverID = data.text("server_id") ?: return
        val deploymentID = RelayServers.target(app.store, serverID)?.first ?: return
        val deployment = app.fleet.deployments.value.firstOrNull { it.id == deploymentID } ?: return
        val at = (data.number("at")?.toLong() ?: (System.currentTimeMillis() / 1000)) * 1000
        val store = FleetSnapshotStore(app)
        val changed = store.updateServer(deployment.id, deployment.name) { server -> apply(server, data, at) }
        if (changed) WidgetRefresh.reload(app)
    }

    /** The readings the push carries, over what the server had */
    fun apply(server: FleetSnapshot.Server, data: JsonObject, at: Long): FleetSnapshot.Server = server.copy(
        services = data.part("services")?.let { services(it, at) } ?: server.services,
        security = data.part("security")?.let { security(it, at) } ?: server.security,
        backups = data.part("backups")?.let { backups(it, at) } ?: server.backups,
        metrics = data.part("metrics")?.let { metrics(it, at) } ?: server.metrics,
    )

    private fun services(part: JsonObject, at: Long) =
        FleetSnapshot.ServicesSummary(part.int("total") ?: 0, part.int("attention") ?: 0, at)
            .takeIf { it.total > 0 }

    private fun security(part: JsonObject, at: Long) = FleetSnapshot.SecuritySummary(
        isPresent = part.flag("present"), engineRunning = part.flag("engine"), bouncerRunning = part.flag("bouncer"),
        alertsLast24h = part.int("alerts") ?: 0, localBans = part.int("bans") ?: 0,
        communityBlocklistIPs = part.int("blocklist") ?: 0, takenAt = at,
    )

    private fun backups(part: JsonObject, at: Long) = FleetSnapshot.BackupsSummary(
        isOn = part.flag("on"), everyHours = part.int("every_hours"), everyDays = part.int("every_days"),
        servicesCovered = part.int("services") ?: 0, retention = part.int("retention") ?: 0, takenAt = at,
    )

    private fun metrics(part: JsonObject, at: Long): FleetSnapshot.Reading? {
        val memTotal = part.number("mem_total")?.toLong() ?: return null
        return FleetSnapshot.Reading(
            cpuPercent = part.number("cpu"), memUsedBytes = part.number("mem_used")?.toLong() ?: 0, memTotalBytes = memTotal,
            diskUsedBytes = part.number("disk_used")?.toLong() ?: 0, diskTotalBytes = part.number("disk_total")?.toLong() ?: 0,
            takenAt = at,
        )
    }

    private fun JsonObject.part(key: String): JsonObject? = runCatching { get(key)?.jsonObject }.getOrNull()
    private fun JsonObject.text(key: String): String? = runCatching { get(key)?.jsonPrimitive?.content }.getOrNull()
    private fun JsonObject.number(key: String): Double? = runCatching { get(key)?.jsonPrimitive?.doubleOrNull }.getOrNull()
    private fun JsonObject.int(key: String): Int? = runCatching { get(key)?.jsonPrimitive?.intOrNull }.getOrNull()
    private fun JsonObject.flag(key: String): Boolean = runCatching { get(key)?.jsonPrimitive?.booleanOrNull }.getOrNull() ?: false
}
