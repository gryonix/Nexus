package com.skaymer.gryonixnexus.app.widgets

import android.content.ComponentName
import android.content.Context
import android.service.quicksettings.TileService
import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.AutoBackupSettings
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostMetricsSnapshot
import com.skaymer.gryonixnexus.servercontrol.HostSecurityStatus
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

/** What the app has read, written where the widgets look */
object WidgetFeed {
    @Volatile
    private var context: Context? = null

    fun attach(context: Context) {
        this.context = context.applicationContext
    }

    fun metrics(deployment: Deployment, host: SSHHostID, snapshot: HostMetricsSnapshot, label: String) {
        if (host != deployment.servicesHost) return
        val reading = FleetSnapshot.Reading(
            cpuPercent = snapshot.cpuPercent, memUsedBytes = snapshot.memUsedBytes, memTotalBytes = snapshot.memTotalBytes,
            diskUsedBytes = snapshot.diskUsedBytes, diskTotalBytes = snapshot.diskTotalBytes,
            machineLabel = label, takenAt = System.currentTimeMillis(),
        )
        server(deployment) { it.copy(metrics = reading) }
    }

    fun services(deployment: Deployment, total: Int, needingAttention: Int) {
        if (total == 0) return
        server(deployment) {
            it.copy(services = FleetSnapshot.ServicesSummary(total, needingAttention, System.currentTimeMillis()))
        }
    }

    fun security(deployment: Deployment, status: HostSecurityStatus) {
        val summary = FleetSnapshot.SecuritySummary(
            status.isPresent, status.engineRunning, status.bouncerRunning, status.alertsLast24h,
            status.localBans, status.communityBlocklistIps, System.currentTimeMillis(),
        )
        server(deployment) { it.copy(security = summary) }
    }

    fun backups(deployment: Deployment, settings: AutoBackupSettings) {
        val schedule = settings.schedule
        val summary = FleetSnapshot.BackupsSummary(
            isOn = settings.isOn,
            everyHours = (schedule as? CommandCatalog.Backups.Schedule.Hours)?.count,
            everyDays = (schedule as? CommandCatalog.Backups.Schedule.Days)?.count,
            servicesCovered = settings.services.size,
            retention = settings.retention,
            takenAt = System.currentTimeMillis(),
        )
        server(deployment) { it.copy(backups = summary) }
    }

    fun updates(deployment: Deployment, waiting: Int, checked: Int) {
        if (checked == 0) return
        server(deployment) {
            it.copy(updates = FleetSnapshot.UpdatesSummary(waiting, checked, null, System.currentTimeMillis()))
        }
    }

    /** One protocol's devices, or why the server did not answer */
    fun devices(deployment: Deployment, protocol: ServiceID, names: List<String>?, failure: String?) {
        if (DemoDeployments.isDemoID(deployment.id)) return
        val store = store() ?: return
        val reading = names?.let { FleetSnapshot.ProtocolDevices(protocol.rawValue, it.size, it.take(6)) }
        if (store.upsertProtocol(deployment.id, deployment.name, reading, failure)) refresh()
    }

    fun tunnel(tunnel: TunnelSnapshot) {
        val store = store() ?: return
        if (store.writeTunnel(tunnel)) refresh()
        context?.let { TileService.requestListeningState(it, ComponentName(it, VpnTileService::class.java)) }
    }

    fun forget(deploymentID: String) {
        val store = store() ?: return
        if (store.forgetServer(deploymentID)) refresh()
    }

    private fun server(deployment: Deployment, change: (FleetSnapshot.Server) -> FleetSnapshot.Server) {
        if (DemoDeployments.isDemoID(deployment.id)) return
        val store = store() ?: return
        if (store.updateServer(deployment.id, deployment.name, change)) refresh()
    }

    private fun store(): FleetSnapshotStore? = context?.let(::FleetSnapshotStore)

    private fun refresh() {
        context?.let(WidgetRefresh::reload)
    }
}
