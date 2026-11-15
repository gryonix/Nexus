package com.skaymer.gryonixnexus.app.notify

import com.skaymer.gryonixnexus.app.shell.SettingsStore
import gryonixnexusd.v1.NotifyChecks

/** What this device wants to hear about, for every server */
data class NotifyPreferences(
    val disks: Boolean = true,
    val spacePercent: Int = 90,
    val services: Boolean = true,
    val backups: Boolean = true,
    val agentUpdate: Boolean = true,
    val appUpdate: Boolean = true,
    val operations: Boolean = false,
    val sshLogins: Boolean = true,
    val unusualLoad: Boolean = true,
    val widgetMinutes: Int = 60,
) {
    /** The checks a server runs for these wishes */
    val checks: NotifyChecks
        get() = NotifyChecks(
            raid = disks,
            smart = disks,
            disk_space = disks,
            disk_space_percent = spacePercent,
            services = services,
            backups = backups,
            agent_update = agentUpdate,
            operations = operations,
            ssh_logins = sshLogins,
            unusual_load = unusualLoad,
            widget_refresh_minutes = widgetMinutes,
        )

    /** Relay announcements this device turns down */
    val muted: List<String> get() = if (appUpdate) emptyList() else listOf(APP_UPDATE_TOPIC)

    /** A fingerprint to tell whether a server is in step */
    val fingerprint: String
        get() = listOf(disks, services, backups, agentUpdate, appUpdate, operations, sshLogins, unusualLoad).joinToString("") { if (it) "1" else "0" } +
            spacePercent + "w" + widgetMinutes

    fun save(store: SettingsStore) {
        store.setBoolean(DISKS, disks)
        store.setString(SPACE_PERCENT, spacePercent.toString())
        store.setBoolean(SERVICES, services)
        store.setBoolean(BACKUPS, backups)
        store.setBoolean(AGENT_UPDATE, agentUpdate)
        store.setBoolean(APP_UPDATE, appUpdate)
        store.setBoolean(OPERATIONS, operations)
        store.setBoolean(SSH_LOGINS, sshLogins)
        store.setBoolean(UNUSUAL_LOAD, unusualLoad)
        store.setString(WIDGET_MINUTES, widgetMinutes.toString())
    }

    companion object {
        const val DISKS = "notify.disks"
        const val SPACE_PERCENT = "notify.spacePercent"
        const val SERVICES = "notify.services"
        const val BACKUPS = "notify.backups"
        const val AGENT_UPDATE = "notify.agentUpdate"
        const val APP_UPDATE = "notify.appUpdate"
        const val OPERATIONS = "notify.operations"
        const val SSH_LOGINS = "notify.sshLogins"
        const val UNUSUAL_LOAD = "notify.unusualLoad"
        const val WIDGET_MINUTES = "notify.widgetMinutes"

        /** How often a server may refresh the widgets */
        val WIDGET_MINUTE_CHOICES = listOf(15, 30, 60, 180)
        const val APP_UPDATE_TOPIC = "app_update"

        fun load(store: SettingsStore): NotifyPreferences = NotifyPreferences(
            disks = store.boolean(DISKS) ?: true,
            spacePercent = store.string(SPACE_PERCENT)?.toIntOrNull()?.takeIf { it in 50..99 } ?: 90,
            services = store.boolean(SERVICES) ?: true,
            backups = store.boolean(BACKUPS) ?: true,
            agentUpdate = store.boolean(AGENT_UPDATE) ?: true,
            appUpdate = store.boolean(APP_UPDATE) ?: true,
            operations = store.boolean(OPERATIONS) ?: false,
            sshLogins = store.boolean(SSH_LOGINS) ?: true,
            unusualLoad = store.boolean(UNUSUAL_LOAD) ?: true,
            widgetMinutes = store.string(WIDGET_MINUTES)?.toIntOrNull()?.takeIf { it in WIDGET_MINUTE_CHOICES } ?: 60,
        )

        fun syncedKey(deploymentID: String) = "notify.synced.$deploymentID"

        /** One server's own checks, as wishes */
        fun from(checks: NotifyChecks): NotifyPreferences = NotifyPreferences(
            disks = checks.raid || checks.disk_space,
            spacePercent = checks.disk_space_percent.takeIf { it in 50..99 } ?: 90,
            services = checks.services,
            backups = checks.backups,
            agentUpdate = checks.agent_update,
            operations = checks.operations,
            sshLogins = checks.ssh_logins,
            unusualLoad = checks.unusual_load,
        )
    }
}
