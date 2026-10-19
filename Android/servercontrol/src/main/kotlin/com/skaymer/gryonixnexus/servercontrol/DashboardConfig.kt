package com.skaymer.gryonixnexus.servercontrol

import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.serialization.Serializable

@Serializable
data class DashboardConfig(
    // Connection
    val vpsHost: String = "",
    val sshPort: Int = 22,
    /** Same login on both machines; also the sudoers subject */
    val sshUser: String = "",
    val homeWGAddress: String = "10.8.0.2",
    val wgInterface: String = "wg0",

    val mailcowPath: String = "/opt/mailcow-dockerized",
    val vaultwardenContainer: String = "vaultwarden",
    val vaultwardenDataPath: String = "/opt/vaultwarden/data",
    val mailcowBackupDir: String = "/opt/backups/mailcow",
    val vaultwardenBackupDir: String = "/opt/backups/vaultwarden",
    val backupRetention: Int = 7,

    // Timeouts, seconds
    val quickTimeoutSeconds: Int = 15,
    val restartTimeoutSeconds: Int = 60,
    val mailcowRestartTimeoutSeconds: Int = 120,
    /** Mailcow update and backups can run up to ten minutes */
    val longTimeoutSeconds: Int = 600,
) {
    val quickTimeout: Duration get() = quickTimeoutSeconds.seconds
    val restartTimeout: Duration get() = restartTimeoutSeconds.seconds
    val mailcowRestartTimeout: Duration get() = mailcowRestartTimeoutSeconds.seconds
    val longTimeout: Duration get() = longTimeoutSeconds.seconds

    /** Minimum needed to open a connection */
    val isConnectable: Boolean
        get() = vpsHost.isNotEmpty() && sshUser.isNotEmpty() && sshPort in 1..65535

    companion object {
        val DEFAULT = DashboardConfig()
    }
}
