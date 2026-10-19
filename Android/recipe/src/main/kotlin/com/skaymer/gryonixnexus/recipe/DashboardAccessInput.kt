package com.skaymer.gryonixnexus.recipe

data class DashboardAccessInput(
    val sshUser: String,
    val createUser: Boolean = true,
    /** Full authorized_keys line, e.g */
    val appPublicKey: String,
    val mailcowPath: String = "/opt/mailcow-dockerized",
    val vaultwardenContainer: String = "vaultwarden",
    val vaultwardenDataPath: String = "/opt/vaultwarden/data",
    val mailcowBackupDir: String = "/opt/backups/mailcow",
    val vaultwardenBackupDir: String = "/opt/backups/vaultwarden",
    val backupRetention: Int = 7
) {
    /** Archives rotation keeps, never fewer than one */
    val keptBackups: Int get() = maxOf(backupRetention, 1)

    val hasValidUser: Boolean
        get() {
            val first = sshUser.firstOrNull() ?: return false
            if (!(first.isLowerCase() || first == '_')) return false
            return sshUser.all { it.isLowerCase() || it.isDigit() || it == '_' || it == '-' } &&
                sshUser.length <= 32
        }

    val hasValidKey: Boolean
        get() = appPublicKey.startsWith("ssh-ed25519 ") && !appPublicKey.contains("\n")

    /** Docker container name: alphanumeric start, then [a-zA-Z0-9_.-] */
    val hasValidContainerName: Boolean
        get() {
            val first = vaultwardenContainer.firstOrNull() ?: return false
            if (!(first.isLetter() || first.isDigit())) return false
            return vaultwardenContainer.all {
                it.isLetter() || it.isDigit() || it == '_' || it == '.' || it == '-'
            }
        }

    val hasValidPaths: Boolean
        get() = listOf(mailcowPath, vaultwardenDataPath, mailcowBackupDir, vaultwardenBackupDir)
            .all { path ->
                path.startsWith("/") && path.length > 1 && !path.endsWith("/") &&
                    path.all {
                        it.isLetter() || it.isDigit() || it == '/' || it == '_' ||
                            it == '.' || it == '-'
                    }
            }

    companion object {
        const val DEFAULT_USER = "server-user"
    }
}
