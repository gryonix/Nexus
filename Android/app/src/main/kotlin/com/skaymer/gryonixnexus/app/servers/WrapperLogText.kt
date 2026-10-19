package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.servercontrol.CommandMarkers

object WrapperLogText {
    private val PROTOCOL = listOf(
        CommandMarkers.Update.DONE,
        CommandMarkers.Update.UPDATED,
        CommandMarkers.Update.ROLLED_BACK,
        CommandMarkers.Update.FAILED,
        CommandMarkers.Update.AVAILABLE,
        CommandMarkers.Update.CURRENT,
        CommandMarkers.Update.UNKNOWN,
        CommandMarkers.Backups.CONTROL_DONE,
        CommandMarkers.Backups.BACKUP_DONE,
        CommandMarkers.Backups.ESTIMATE,
        CommandMarkers.Restore.DONE,
        CommandMarkers.Uninstall.DONE,
    )

    /** Stages a wrapper line can announce */
    enum class Stage { BACKUP, WAITING }

    /** The stage a known wrapper line announces */
    fun stage(line: String): Stage? {
        val text = line.trim()
        return when {
            text.startsWith("backing up ") -> Stage.BACKUP
            text.startsWith("waiting for ") -> Stage.WAITING
            else -> null
        }
    }

    fun readable(text: String): String = text
        .lineSequence()
        .filterNot { line -> PROTOCOL.any { marker -> line.trimStart().startsWith(marker) } }
        .joinToString("\n")
        .replace(Regex("\n{3,}"), "\n\n")
}
