package com.skaymer.gryonixnexus.servercontrol

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CommandCatalogGoldenTest {
    private fun golden(): List<Pair<String, String>> {
        val text = checkNotNull(javaClass.getResourceAsStream("/swift-commands-golden.json"))
            .bufferedReader().readText()
        val entries = mutableListOf<Pair<String, String>>()
        val regex = Regex("""\{\s*"name"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,\s*"value"\s*:\s*"((?:[^"\\]|\\.)*)"\s*}""")
        for (match in regex.findAll(text)) {
            entries += unescape(match.groupValues[1]) to unescape(match.groupValues[2])
        }
        val objects = Regex("\"name\"\\s*:").findAll(text).count()
        check(entries.size == objects) {
            "the golden holds $objects commands and only ${entries.size} parsed — " +
                "the reader is dropping entries silently"
        }
        return entries
    }

    private fun unescape(raw: String): String {
        val out = StringBuilder()
        var i = 0
        while (i < raw.length) {
            val c = raw[i]
            if (c != '\\') { out.append(c); i++; continue }
            when (val next = raw[i + 1]) {
                'n' -> { out.append('\n'); i += 2 }
                't' -> { out.append('\t'); i += 2 }
                'r' -> { out.append('\r'); i += 2 }
                'b' -> { out.append('\b'); i += 2 }
                '"' -> { out.append('"'); i += 2 }
                '\\' -> { out.append('\\'); i += 2 }
                '/' -> { out.append('/'); i += 2 }
                'u' -> { out.append(raw.substring(i + 2, i + 6).toInt(16).toChar()); i += 6 }
                else -> { out.append(next); i += 2 }
            }
        }
        return out.toString()
    }

    private val path = "/opt/back ups/o'brien"
    private val quoted = "it's here"

    private fun kotlinCommands(): List<Pair<String, String>> = buildList {
        hostCommands()
        metricsHistoryCommands()
        scheduleCommands()
    }

    private fun MutableList<Pair<String, String>>.emit(name: String, value: String) {
        add(name to value)
    }

    private fun MutableList<Pair<String, String>>.hostCommands() {
        emit("ipForwardingCheck", CommandCatalog.IP_FORWARDING_CHECK)
        emit("pingSelf", CommandCatalog.pingSelf("203.0.113.10"))
        emit("pingSelf.quoting", CommandCatalog.pingSelf(quoted))
        emit("generalProbeSeparator", CommandCatalog.GENERAL_PROBE_SEPARATOR)
        emit("generalProbe", CommandCatalog.generalProbe("203.0.113.10", "10.8.0.2"))
        emit("pingTunnel", CommandCatalog.pingTunnel("10.8.0.2"))
        emit("restartWireGuard", CommandCatalog.restartWireGuard("wg0"))
        emit("restartSSHD", CommandCatalog.RESTART_SSHD)
        emit("rebootHost", CommandCatalog.REBOOT_HOST)
        emit("powerOffHost", CommandCatalog.POWER_OFF_HOST)
        emit("wgShow", CommandCatalog.WG_SHOW)
        emit("disk", CommandCatalog.DISK)
        emit("memory", CommandCatalog.MEMORY)
        emit("hostMetrics", CommandCatalog.HOST_METRICS)
        emit("installReport", CommandCatalog.INSTALL_REPORT)

        emit("adminLockdown.on", CommandCatalog.AdminLockdown.ON)
        emit("adminLockdown.off", CommandCatalog.AdminLockdown.OFF)
        emit("adminLockdown.status", CommandCatalog.AdminLockdown.STATUS)
        emit("adminLockdown.only",
             CommandCatalog.AdminLockdown.only(listOf("mail.example.com", "vault.example.com")))
        emit("adminLockdown.only.empty", CommandCatalog.AdminLockdown.only(emptyList()))
        for (host in listOf("mail.example.com", "", "bad host", "bad_host", "ok-1.example")) {
            emit("adminLockdown.isValidHost[$host]",
                 CommandCatalog.AdminLockdown.isValidHost(host).toString())
        }

        emit("containers.controlScriptPath", CommandCatalog.Containers.CONTROL_SCRIPT_PATH)
        for (action in CommandCatalog.Containers.Action.entries) {
            emit("containers.control.${action.rawValue}",
                 CommandCatalog.Containers.control(action, "vaultwarden"))
        }
        emit("containers.control.quoting",
             CommandCatalog.Containers.control(CommandCatalog.Containers.Action.RESTART, quoted))

        emit("restore.scriptPath", CommandCatalog.Restore.SCRIPT_PATH)
        emit("restore.doneMarker", CommandCatalog.Restore.DONE_MARKER)
        emit("restore.run", CommandCatalog.Restore.run("vaultwarden", path))
        emit("restore.stagingDirectoryName", CommandCatalog.Restore.STAGING_DIRECTORY_NAME)
        emit("restore.stagingDirectory", CommandCatalog.Restore.stagingDirectory("/opt/backups"))
        for (target in listOf("vaultwarden", "", "Vaultwarden", "docker-mailserver", "vault_warden")) {
            emit("restore.isValidTarget[$target]", CommandCatalog.Restore.isValidTarget(target).toString())
        }
        for (candidate in listOf("/opt/backups/a.tar.gz", "/opt/backupsX/a.tar.gz", "/opt/backups/../etc/passwd")) {
            emit("restore.isValidArchivePath[$candidate]",
                 CommandCatalog.Restore.isValidArchivePath(candidate, "/opt/backups").toString())
        }

        emit("uninstall.scriptPath", CommandCatalog.Uninstall.SCRIPT_PATH)
        emit("uninstall.doneMarker", CommandCatalog.Uninstall.DONE_MARKER)
        emit("uninstall.vpnTarget", CommandCatalog.Uninstall.VPN_TARGET)
        emit("uninstall.purgeDataFlag", CommandCatalog.Uninstall.PURGE_DATA_FLAG)
        emit("uninstall.purgeBackupsFlag", CommandCatalog.Uninstall.PURGE_BACKUPS_FLAG)
        for (purge in listOf(PurgeOptions.NONE, PurgeOptions(data = true),
                             PurgeOptions(backups = true), PurgeOptions(data = true, backups = true))) {
            val tag = "${purge.data}-${purge.backups}"
            emit("uninstall.run[$tag]", CommandCatalog.Uninstall.run("vaultwarden", purge))
            emit("uninstall.fullCleanup[$tag]", CommandCatalog.Uninstall.fullCleanup(purge))
        }
    }

    private fun MutableList<Pair<String, String>>.metricsHistoryCommands() {
        for (bucket in MetricsHistoryBucket.entries) {
            emit("metricsHistory.${bucket.rawValue}", CommandCatalog.metricsHistory(bucket))
            emit("diskHistory.${bucket.rawValue}", CommandCatalog.diskHistory(bucket))
        }

        emit("mailcow.status", CommandCatalog.Mailcow.STATUS)
        emit("mailcow.restart", CommandCatalog.Mailcow.RESTART)
        emit("mailcow.update", CommandCatalog.Mailcow.update("/opt/mailcow-dockerized"))
        emit("mailcow.backup", CommandCatalog.Mailcow.backup("/opt/mailcow-dockerized", path))
        emit("mailcow.latestBackupSize", CommandCatalog.Mailcow.latestBackupSize("/opt/backups"))
        emit("mailcow.dkimScriptPath", CommandCatalog.Mailcow.DKIM_SCRIPT_PATH)
        emit("mailcow.dkimDoneMarker", CommandCatalog.Mailcow.DKIM_DONE_MARKER)
        emit("mailcow.dkimDump", CommandCatalog.Mailcow.DKIM_DUMP)

        emit("dms.mailboxScriptPath", CommandCatalog.DockerMailserver.MAILBOX_SCRIPT_PATH)
        emit("dms.mailboxDoneMarker", CommandCatalog.DockerMailserver.MAILBOX_DONE_MARKER)
        emit("dms.listMailboxes", CommandCatalog.DockerMailserver.LIST_MAILBOXES)
        emit("dms.addMailbox", CommandCatalog.DockerMailserver.addMailbox("user@example.com"))
        emit("dms.deleteMailbox", CommandCatalog.DockerMailserver.deleteMailbox("user@example.com"))
        emit("dms.setMailboxPassword", CommandCatalog.DockerMailserver.setMailboxPassword("user@example.com"))
        for (address in listOf("user@example.com", "", "-user@example.com", "user@", "@example.com",
                               "a@b@c", "user+tag@example.com", "usér@example.com", "user example@x.com")) {
            emit("dms.isValidAddress[$address]",
                 CommandCatalog.DockerMailserver.isValidAddress(address).toString())
        }

        emit("vaultwarden.status", CommandCatalog.Vaultwarden.STATUS)
        emit("vaultwarden.restart", CommandCatalog.Vaultwarden.restart("vaultwarden"))
        emit("vaultwarden.update", CommandCatalog.Vaultwarden.UPDATE)
        emit("vaultwarden.stop", CommandCatalog.Vaultwarden.stop("vaultwarden"))
        emit("vaultwarden.start", CommandCatalog.Vaultwarden.start("vaultwarden"))
        emit("vaultwarden.stagingArchivePath",
             CommandCatalog.Vaultwarden.stagingArchivePath("/opt/backups", "vaultwarden"))
        emit("vaultwarden.archive", CommandCatalog.Vaultwarden.archive("/opt/vaultwarden/data", path))
        emit("vaultwarden.chownArchive",
             CommandCatalog.Vaultwarden.chownArchive("server-user", "/opt/backups/a.tar.gz"))
        emit("vaultwarden.encrypt",
             CommandCatalog.Vaultwarden.encrypt(path, "/opt/backups/a.gpg"))
        emit("vaultwarden.removePlainArchive", CommandCatalog.Vaultwarden.removePlainArchive(path))
        emit("vaultwarden.backupSize", CommandCatalog.Vaultwarden.backupSize(path))
        emit("vaultwarden.rotate", CommandCatalog.Vaultwarden.rotate("/opt/backups", 7))

        emit("backups.listMailcow", CommandCatalog.Backups.listMailcow(path))
        emit("backups.listVaultwarden", CommandCatalog.Backups.listVaultwarden("/opt/backups"))
        emit("backups.makeDir", CommandCatalog.Backups.makeDir(path))
        emit("backups.latestEntrySize", CommandCatalog.Backups.latestEntrySize("/opt/backups"))
        emit("backups.latestShareableFile", CommandCatalog.Backups.latestShareableFile("/opt/backups"))
        emit("backups.controlScriptPath", CommandCatalog.Backups.CONTROL_SCRIPT_PATH)
        emit("backups.controlDoneMarker", CommandCatalog.Backups.CONTROL_DONE_MARKER)
        emit("backups.backupDoneMarker", CommandCatalog.Backups.BACKUP_DONE_MARKER)
        emit("backups.estimateMarker", CommandCatalog.Backups.ESTIMATE_MARKER)
        emit("backups.encryptFlag", CommandCatalog.Backups.ENCRYPT_FLAG)
        emit("backups.noEncryptFlag", CommandCatalog.Backups.NO_ENCRYPT_FLAG)
        emit("backups.run.encrypted", CommandCatalog.Backups.run("vaultwarden", true))
        emit("backups.run.plain", CommandCatalog.Backups.run("vaultwarden", false))
        emit("backups.estimate", CommandCatalog.Backups.estimate("vaultwarden"))
        emit("backups.delete", CommandCatalog.Backups.delete(path))
        emit("backups.readSchedule", CommandCatalog.Backups.READ_SCHEDULE)
        emit("backups.setPassphrase", CommandCatalog.Backups.SET_PASSPHRASE)
    }

    private fun MutableList<Pair<String, String>>.scheduleCommands() {
        val schedules = listOf(
            "off" to CommandCatalog.Backups.Schedule.Off,
            "hours-6-30" to CommandCatalog.Backups.Schedule.Hours(6, 30),
            "hours-0-99" to CommandCatalog.Backups.Schedule.Hours(0, 99),
            "hours-99--5" to CommandCatalog.Backups.Schedule.Hours(99, -5),
            "days-1-4-5" to CommandCatalog.Backups.Schedule.Days(1, 4, 5),
            "days-99-99-99" to CommandCatalog.Backups.Schedule.Days(99, 99, 99),
            "days-0--1--1" to CommandCatalog.Backups.Schedule.Days(0, -1, -1),
        )
        for ((tag, schedule) in schedules) {
            emit("schedule.wrapperArgument[$tag]", schedule.wrapperArgument)
            emit("schedule.isOn[$tag]", schedule.isOn.toString())
            emit("backups.setSchedule[$tag]",
                 CommandCatalog.Backups.setSchedule(schedule, 7, listOf("vaultwarden", "nextcloud")))
            emit("backups.setSchedule.noServices[$tag]",
                 CommandCatalog.Backups.setSchedule(schedule, 3, emptyList()))
            emit("updates.setSchedule[$tag]",
                 CommandCatalog.Updates.setSchedule(schedule, listOf("vaultwarden")))
            emit("updates.setSchedule.noServices[$tag]",
                 CommandCatalog.Updates.setSchedule(schedule, emptyList()))
        }
        for (argument in listOf("off", "every:6h@00:30", "every:1d@04:05", "garbage",
                                "every:6x@00:30", "every:6h", "every:6h@ab:cd")) {
            emit("schedule.parse[$argument]",
                 CommandCatalog.Backups.Schedule.fromWrapperArgument(argument).wrapperArgument)
        }

        emit("updates.controlScriptPath", CommandCatalog.Updates.CONTROL_SCRIPT_PATH)
        emit("updates.doneMarker", CommandCatalog.Updates.DONE_MARKER)
        emit("updates.availableMarker", CommandCatalog.Updates.AVAILABLE_MARKER)
        emit("updates.currentMarker", CommandCatalog.Updates.CURRENT_MARKER)
        emit("updates.unknownMarker", CommandCatalog.Updates.UNKNOWN_MARKER)
        emit("updates.updatedMarker", CommandCatalog.Updates.UPDATED_MARKER)
        emit("updates.rolledBackMarker", CommandCatalog.Updates.ROLLED_BACK_MARKER)
        emit("updates.failedMarker", CommandCatalog.Updates.FAILED_MARKER)
        emit("updates.check.all", CommandCatalog.Updates.check(null))
        emit("updates.check.one", CommandCatalog.Updates.check("vaultwarden"))
        emit("updates.run", CommandCatalog.Updates.run("vaultwarden"))
        emit("updates.readSchedule", CommandCatalog.Updates.READ_SCHEDULE)
        emit("updates.readStatus", CommandCatalog.Updates.READ_STATUS)

        val sampleKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB4Gr/xample+Key/Only gryonixnexus-app"
        emit("accessGrant.marker", AccessGrantCommand.MARKER)
        emit("accessGrant.command", AccessGrantCommand.command(sampleKey))
        emit("accessGrant.quoting", AccessGrantCommand.command("ssh-ed25519 AAA'B comment"))
        emit("shellUser.marker", ShellUserCommand.MARKER)
        emit("shellUser.command", ShellUserCommand.command("dana", sampleKey, sudo = false) ?: "<nil>")
        emit("shellUser.command.sudo", ShellUserCommand.command("dana", sampleKey, sudo = true) ?: "<nil>")
        emit("shellUser.command.reserved", ShellUserCommand.command("root", sampleKey, sudo = true) ?: "<nil>")
        emit("shellUser.command.invalid", ShellUserCommand.command("Dana", sampleKey, sudo = false) ?: "<nil>")

        val keyBytes = ByteArray(32) { ((it * 7) % 251).toByte() }
        emit("openSSHPublicKey.defaultComment", OpenSSHPublicKey.DEFAULT_COMMENT)
        emit("openSSHPublicKey.encode", OpenSSHPublicKey.encode(keyBytes, OpenSSHPublicKey.DEFAULT_COMMENT))
        emit("openSSHPublicKey.encode.comment", OpenSSHPublicKey.encode(keyBytes, "someone@host"))
    }

    @Test
    fun `every command matches the swift original byte for byte`() {
        val expected = golden()
        assertTrue(expected.size > 100, "the golden did not parse — ${expected.size} entries read")
        val actual = kotlinCommands()
        assertEquals(expected.map { it.first }, actual.map { it.first },
                     "the two sides no longer emit the same set of commands, in the same order")
        for ((index, pair) in expected.withIndex()) {
            assertEquals(pair.second, actual[index].second,
                         "command '${pair.first}' differs from the Swift original")
        }
    }
}
