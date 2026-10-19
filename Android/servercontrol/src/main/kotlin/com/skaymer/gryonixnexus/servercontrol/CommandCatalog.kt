package com.skaymer.gryonixnexus.servercontrol

import com.skaymer.gryonixnexus.catalog.BackupSpec

/** What a removal additionally deletes from disk */
data class PurgeOptions(val data: Boolean = false, val backups: Boolean = false) {
    val isEmpty: Boolean get() = !data && !backups

    companion object {
        val NONE = PurgeOptions()
    }
}

/** Every remote command the dashboard sends, as exact literals */
object CommandCatalog {
    const val IP_FORWARDING_CHECK = "sudo sysctl net.ipv4.ip_forward"

    fun pingSelf(vpsHost: String): String =
        "ping -c 1 -W 2 ${ShellQuoting.singleQuoted(vpsHost)}"

    const val GENERAL_PROBE_SEPARATOR = "___GRYONIXNEXUS_NEXT___"

    fun generalProbe(vpsHost: String, homeWGAddress: String): String =
        listOf(IP_FORWARDING_CHECK, pingSelf(vpsHost), pingTunnel(homeWGAddress))
            .joinToString(separator = "; echo '$GENERAL_PROBE_SEPARATOR'; ")

    fun pingTunnel(homeWGAddress: String): String =
        "ping -c 1 -W 2 ${ShellQuoting.singleQuoted(homeWGAddress)}"

    fun restartWireGuard(interfaceName: String): String =
        "sudo systemctl restart wg-quick@$interfaceName"

    const val RESTART_SSHD = "sudo systemctl restart sshd"

    /** Reboots the host */
    const val REBOOT_HOST = "sudo systemctl reboot"
    const val POWER_OFF_HOST = "sudo systemctl poweroff"

    const val DEFAULT_ROUTE_MAC_ADDRESS =
        "cat /sys/class/net/\$(ip route show default | awk '{print \$5; exit}')/address"

    const val WG_SHOW = "sudo wg show"

    /** VPN-only access switch for admin web panels */
    object AdminLockdown {
        const val ON = "sudo /opt/gryonixnexus-admin-lockdown.sh on"
        const val OFF = "sudo /opt/gryonixnexus-admin-lockdown.sh off"
        const val STATUS = "sudo /opt/gryonixnexus-admin-lockdown.sh status"

        /** Guard only the given vhosts */
        fun only(hosts: List<String>): String =
            "sudo /opt/gryonixnexus-admin-lockdown.sh only " + hosts.joinToString(" ")

        /** Client-side mirror of the wrapper's host validation */
        fun isValidHost(host: String): Boolean =
            host.isNotEmpty() && host.all { it.code < 128 && (it.isLetter() || it.isDigit() || it == '.' || it == '-') }
    }

    object Containers {
        /** Root-owned wrapper the setup scripts install on every docker host */
        const val CONTROL_SCRIPT_PATH = "/opt/gryonixnexus-container-ctl.sh"

        enum class Action(val rawValue: String) {
            START("start"), STOP("stop"), RESTART("restart")
        }

        /** `sudo <wrapper> <action> <container>` */
        fun control(action: Action, container: String): String =
            "sudo $CONTROL_SCRIPT_PATH ${action.rawValue} ${ShellQuoting.singleQuoted(container)}"
    }

    object Restore {
        /** Root-owned wrapper installed alongside the container one */
        const val SCRIPT_PATH = "/opt/gryonixnexus-restore.sh"

        /** Last line the wrapper prints on success — see [CommandMarkers] */
        const val DONE_MARKER = CommandMarkers.Restore.DONE

        fun isValidTarget(target: String): Boolean =
            target.isNotEmpty() && target.all {
                it.code < 128 && (it.isLowerCase() || it.isDigit() || it == '-')
            }

        /** `sudo <wrapper> <service> <archive>` */
        fun run(target: String, archivePath: String): String =
            "sudo $SCRIPT_PATH $target ${ShellQuoting.singleQuoted(archivePath)}"

        const val STAGING_DIRECTORY_NAME = "incoming"

        fun stagingDirectory(backupDir: String): String = "$backupDir/$STAGING_DIRECTORY_NAME"

        fun isValidArchivePath(path: String, backupDir: String): Boolean =
            path.startsWith("$backupDir/") && !path.contains("..")
    }

    object Uninstall {
        const val SCRIPT_PATH = "/opt/gryonixnexus-uninstall.sh"
        const val DONE_MARKER = CommandMarkers.Uninstall.DONE

        const val VPN_TARGET = "vpn"

        const val PURGE_DATA_FLAG = "--purge-data"
        const val PURGE_BACKUPS_FLAG = "--purge-backups"

        /** `sudo <wrapper> <target> [--purge-data] [--purge-backups]` */
        fun run(target: String, purge: PurgeOptions): String =
            "sudo $SCRIPT_PATH $target${flags(purge)}"

        fun fullCleanup(purge: PurgeOptions): String = "sudo $SCRIPT_PATH --all${flags(purge)}"

        private fun flags(purge: PurgeOptions): String =
            (if (purge.data) " $PURGE_DATA_FLAG" else "") +
                (if (purge.backups) " $PURGE_BACKUPS_FLAG" else "")
    }

    const val DISK = "df -B1 --output=target,size,used,pcent -x tmpfs -x devtmpfs -x overlay"

    const val MEMORY = "free -b"

    const val HOST_METRICS = "echo @@STAT@@; cat /proc/stat; " +
        "echo @@MEM@@; cat /proc/meminfo; " +
        "echo @@UPTIME@@; cat /proc/uptime; " +
        "echo @@LOAD@@; cat /proc/loadavg; " +
        "echo @@NET@@; cat /proc/net/dev; " +
        "echo @@DISKSTATS@@; cat /proc/diskstats; " +
        "echo @@DF@@; df -B1 --output=target,size,used,pcent -x tmpfs -x devtmpfs -x overlay 2>/dev/null; " +
        "echo @@OS@@; cat /etc/os-release 2>/dev/null; " +
        "echo @@NPROC@@; nproc 2>/dev/null; " +
        "echo @@TEMP@@; cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null; true"

    /** One downsampled history bucket written by the metrics collector */
    fun metricsHistory(bucket: MetricsHistoryBucket): String =
        "cat /var/lib/gryonixnexus/metrics/${bucket.rawValue}.csv 2>/dev/null; " +
            "echo ${MetricsHistoryParser.POWER_MARKER}; " +
            "cat /var/lib/gryonixnexus/metrics/power-${bucket.rawValue}.csv 2>/dev/null; true"

    /** Per-filesystem used and total bytes for one bucket */
    fun diskHistory(bucket: MetricsHistoryBucket): String =
        "cat /var/lib/gryonixnexus/metrics/disks-${bucket.rawValue}.csv 2>/dev/null; true"

    const val INSTALL_REPORT = "cat /var/lib/gryonixnexus/install-report.txt 2>/dev/null; true"

    object Mailcow {
        const val STATUS = "sudo docker compose -p mailcowdockerized ps"

        const val RESTART = "sudo docker compose -p mailcowdockerized restart"

        fun update(mailcowPath: String): String =
            "cd ${ShellQuoting.argument(mailcowPath)} && sudo /bin/bash " +
                "${ShellQuoting.argument("$mailcowPath/update.sh")} --force"

        fun backup(mailcowPath: String, backupDir: String): String =
            "mkdir -p ${ShellQuoting.singleQuoted(backupDir)} && sudo ${ShellQuoting.argument("$mailcowPath/bot-backup.sh")}"

        /** Size of the newest backup produced by the wrapper */
        fun latestBackupSize(backupDir: String): String =
            "du -sh \"$(ls -1dt ${ShellQuoting.argument(backupDir)}/* | head -n 1)\" | tail -n 1"

        /** Root-owned read-only wrapper the mailcow setup installs */
        const val DKIM_SCRIPT_PATH = "/opt/gryonixnexus-dkim.sh"

        const val DKIM_DONE_MARKER = CommandMarkers.Dkim.DONE

        /** `sudo <wrapper>` — re-reads DKIM after the install */
        const val DKIM_DUMP = "sudo $DKIM_SCRIPT_PATH"
    }

    /** Mailbox management for the docker-mailserver engine */
    object DockerMailserver {
        const val MAILBOX_SCRIPT_PATH = "/opt/gryonixnexus-dms-mailbox.sh"

        const val MAILBOX_DONE_MARKER = CommandMarkers.Mailbox.DONE

        /** Read-only listing of the mailboxes the engine knows about */
        const val LIST_MAILBOXES = "sudo $MAILBOX_SCRIPT_PATH list"

        /** `sudo <wrapper> add <address>` — the password is NOT here */
        fun addMailbox(address: String): String =
            "sudo $MAILBOX_SCRIPT_PATH add ${ShellQuoting.singleQuoted(address)}"

        fun deleteMailbox(address: String): String =
            "sudo $MAILBOX_SCRIPT_PATH del ${ShellQuoting.singleQuoted(address)}"

        /** `sudo <wrapper> password <address>` — password on stdin, as above */
        fun setMailboxPassword(address: String): String =
            "sudo $MAILBOX_SCRIPT_PATH password ${ShellQuoting.singleQuoted(address)}"

        fun isValidAddress(address: String): Boolean {
            if (address.isEmpty() || address.startsWith("-")) return false
            val allowed = address.all {
                it.code < 128 && (it.isLetter() || it.isDigit() || it in ".@_+-")
            }
            if (!allowed) return false
            val parts = address.split("@")
            return parts.size == 2 && parts[0].isNotEmpty() && parts[1].isNotEmpty()
        }
    }

    object Vaultwarden {
        const val STATUS = "sudo docker ps -a"

        fun restart(container: String): String = "sudo docker restart ${ShellQuoting.argument(container)}"

        const val UPDATE = "sudo /opt/vaultwarden-update.sh"

        fun stop(container: String): String = "sudo docker stop ${ShellQuoting.argument(container)}"

        fun start(container: String): String = "sudo docker start ${ShellQuoting.argument(container)}"

        fun stagingArchivePath(backupDir: String, container: String): String =
            "$backupDir/$container-backup.tar.gz"

        /** Data is root-owned, hence tar via sudo */
        fun archive(dataPath: String, archivePath: String): String {
            val relative = BackupSpec.archiveRelativePath(dataPath)
            return "sudo tar czf ${ShellQuoting.singleQuoted(archivePath)} -C / " +
                ShellQuoting.singleQuoted(relative)
        }

        fun chownArchive(user: String, archivePath: String): String =
            "sudo chown ${ShellQuoting.singleQuoted(user)} ${ShellQuoting.singleQuoted(archivePath)}"

        /** Symmetric GPG encryption; the passphrase arrives on stdin */
        fun encrypt(archivePath: String, outputPath: String): String =
            "gpg --symmetric --cipher-algo AES256 --batch --pinentry-mode loopback --passphrase-fd 0" +
                " --output ${ShellQuoting.singleQuoted(outputPath)} ${ShellQuoting.singleQuoted(archivePath)}"

        fun removePlainArchive(archivePath: String): String =
            "rm -f ${ShellQuoting.singleQuoted(archivePath)}"

        fun backupSize(gpgPath: String): String =
            "du -sh ${ShellQuoting.singleQuoted(gpgPath)} | cut -f1"

        /** Keeps the newest [retention] archives, at least one */
        fun rotate(backupDir: String, retention: Int): String {
            val dir = ShellQuoting.singleQuoted(backupDir)
            return "ls -1t $dir 2>/dev/null | grep '\\.gpg$' | tail -n +${maxOf(retention, 1) + 1}" +
                " | while IFS= read -r f; do rm -f -- $dir/\"\$f\"; done"
        }
    }

    // MARK: Backup listings

    object Backups {
        fun listMailcow(backupDir: String): String =
            "ls -lht ${ShellQuoting.singleQuoted(backupDir)}"

        fun listVaultwarden(backupDir: String): String = "ls -lht ${ShellQuoting.argument(backupDir)}/*.gpg"

        fun makeDir(dir: String): String = "mkdir -p ${ShellQuoting.singleQuoted(dir)}"

        fun latestEntrySize(dir: String): String =
            "du -sh \"$(ls -1dt ${ShellQuoting.argument(dir)}/* | head -n 1)\" | tail -n 1"

        fun latestShareableFile(dir: String): String =
            "f=\"$(ls -1dt ${ShellQuoting.argument(dir)}/* 2>/dev/null | head -n 1)\"; " +
                "{ [ -f \"\$f\" ] && [ -r \"\$f\" ] && printf '%s\\n' \"\$f\"; } || true"

        /** Root-owned wrapper for backup housekeeping */
        const val CONTROL_SCRIPT_PATH = "/opt/gryonixnexus-backup-ctl.sh"

        const val CONTROL_DONE_MARKER = CommandMarkers.Backups.CONTROL_DONE
        const val BACKUP_DONE_MARKER = CommandMarkers.Backups.BACKUP_DONE
        const val ESTIMATE_MARKER = CommandMarkers.Backups.ESTIMATE

        const val ENCRYPT_FLAG = "--encrypt"
        const val NO_ENCRYPT_FLAG = "--no-encrypt"

        /** `sudo <wrapper> backup <service> [--encrypt|--no-encrypt]` */
        fun run(target: String, encrypt: Boolean): String =
            "sudo $CONTROL_SCRIPT_PATH backup $target ${if (encrypt) ENCRYPT_FLAG else NO_ENCRYPT_FLAG}"

        fun estimate(target: String): String = "sudo $CONTROL_SCRIPT_PATH estimate $target"

        /** `sudo <wrapper> delete <path>` */
        fun delete(path: String): String =
            "sudo $CONTROL_SCRIPT_PATH delete ${ShellQuoting.singleQuoted(path)}"

        const val SHOW_DESTINATION = "sudo $CONTROL_SCRIPT_PATH show-destination"

        /** `sudo <wrapper> set-destination <kind> <host> <port> <user> <path> <bucket> <keep>` */
        fun setDestination(
            kind: String,
            host: String,
            port: Int,
            user: String,
            path: String,
            bucket: String,
            keep: Int,
        ): String {
            val quoted = listOf(kind, host, port.toString(), user, path, bucket, keep.toString())
                .joinToString(" ") { ShellQuoting.singleQuoted(it) }
            return "sudo $CONTROL_SCRIPT_PATH set-destination $quoted"
        }

        /** `sudo <wrapper> test-destination` — one small file, sent for real */
        const val TEST_DESTINATION = "sudo $CONTROL_SCRIPT_PATH test-destination"

        const val SHOW_DRIVES = "sudo $CONTROL_SCRIPT_PATH show-drives"

        /** `sudo <wrapper> set-drives <mode> <0|1> [uuids...]` */
        fun setDrives(mode: String, encrypt: Boolean, uuids: List<String>): String {
            val quoted = (listOf(mode, if (encrypt) "1" else "0") + uuids).joinToString(" ") { ShellQuoting.singleQuoted(it) }
            return "sudo $CONTROL_SCRIPT_PATH set-drives $quoted"
        }

        sealed interface Schedule {
            data object Off : Schedule

            /** Every [count] hours at [minute] of the hour */
            data class Hours(val count: Int, val minute: Int) : Schedule

            /** Every [count] days at [hour]:[minute] */
            data class Days(val count: Int, val hour: Int, val minute: Int) : Schedule

            val isOn: Boolean get() = this != Off

            /** The wrapper's argument */
            val wrapperArgument: String
                get() = when (this) {
                    is Off -> "off"
                    is Hours -> "every:%dh@00:%02d".format(
                        count.coerceIn(1, 23), minute.coerceIn(0, 59))
                    is Days -> "every:%dd@%02d:%02d".format(
                        count.coerceIn(1, 28), hour.coerceIn(0, 23), minute.coerceIn(0, 59))
                }

            companion object {
                /** Parses what [wrapperArgument] writes into the config */
                fun fromWrapperArgument(value: String): Schedule {
                    if (!value.startsWith("every:")) return Off
                    val at = value.indexOf('@')
                    if (at < 0) return Off
                    val every = value.substring(6, at)
                    val parts = value.substring(at + 1).split(":")
                    if (parts.size != 2) return Off
                    val hour = parts[0].toIntOrNull() ?: return Off
                    val minute = parts[1].toIntOrNull() ?: return Off
                    val unit = every.lastOrNull() ?: return Off
                    val count = every.dropLast(1).toIntOrNull() ?: return Off
                    return when (unit) {
                        'h' -> Hours(count = count, minute = minute)
                        'd' -> Days(count = count, hour = hour, minute = minute)
                        else -> Off
                    }
                }
            }
        }

        /** `sudo <wrapper> set-schedule <schedule> <retention> [services...]` */
        fun setSchedule(schedule: Schedule, retention: Int, services: List<String>): String =
            ("sudo $CONTROL_SCRIPT_PATH set-schedule ${schedule.wrapperArgument} $retention " +
                services.joinToString(" ")).trim()

        /** Reads the schedule config */
        const val READ_SCHEDULE = "cat /etc/gryonixnexus/autobackup.conf 2>/dev/null || true"

        /** Stores the passphrase unattended encrypted backups are made with */
        const val SET_PASSPHRASE = "sudo $CONTROL_SCRIPT_PATH set-passphrase"
    }

    // MARK: Updates

    /** The update wrapper's surface */
    object Updates {
        const val CONTROL_SCRIPT_PATH = "/opt/gryonixnexus-update-ctl.sh"
        const val DONE_MARKER = CommandMarkers.Update.DONE
        const val AVAILABLE_MARKER = CommandMarkers.Update.AVAILABLE
        const val CURRENT_MARKER = CommandMarkers.Update.CURRENT
        const val UNKNOWN_MARKER = CommandMarkers.Update.UNKNOWN
        const val UPDATED_MARKER = CommandMarkers.Update.UPDATED
        const val ROLLED_BACK_MARKER = CommandMarkers.Update.ROLLED_BACK
        const val FAILED_MARKER = CommandMarkers.Update.FAILED

        /** Ask what has moved */
        fun check(service: String?): String =
            "sudo $CONTROL_SCRIPT_PATH check ${service ?: "--all"}"

        /** Apply one service's update */
        fun run(service: String): String =
            "sudo $CONTROL_SCRIPT_PATH run ${ShellQuoting.singleQuoted(service)}"

        /** `sudo <wrapper> set-schedule <schedule> [services...]` */
        fun setSchedule(schedule: Backups.Schedule, services: List<String>): String =
            ("sudo $CONTROL_SCRIPT_PATH set-schedule ${schedule.wrapperArgument} " +
                services.joinToString(" ")).trim()

        const val READ_SCHEDULE = "cat /etc/gryonixnexus/autoupdate.conf 2>/dev/null || true"

        const val READ_STATUS = "sudo $CONTROL_SCRIPT_PATH status"
    }
}
