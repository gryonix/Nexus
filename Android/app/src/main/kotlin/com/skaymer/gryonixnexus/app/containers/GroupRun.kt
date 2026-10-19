package com.skaymer.gryonixnexus.app.containers

import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupRunEvent
import com.skaymer.gryonixnexus.agentcontrol.ContainerEventPhase
import com.skaymer.gryonixnexus.agentcontrol.ContainerRemovalEvent
import com.skaymer.gryonixnexus.agentcontrol.ContainerUpdateEvent

enum class GroupOperationKind { UPDATE, BACKUP, REMOVE }

sealed class GroupOutcome {
    object Updated : GroupOutcome()

    object AlreadyCurrent : GroupOutcome()

    data class RolledBack(val why: String) : GroupOutcome()

    data class BackedUp(val path: String?) : GroupOutcome()

    /** [survivors] is what the completed event still listed */
    data class Removed(val survivors: List<String>) : GroupOutcome() {
        val isGone: Boolean get() = survivors.isEmpty()
    }
}

data class GroupRun(
    val key: String,
    val kind: GroupOperationKind,
    val lines: List<String> = emptyList(),
    val isRunning: Boolean = true,
    val outcome: GroupOutcome? = null,
    val failure: String? = null,
    val skippedBackup: Boolean = false,
) {
    val canBeDismissed: Boolean get() = !isRunning

    val mayUpdateWithoutBackup: Boolean
        get() = !isRunning &&
            kind == GroupOperationKind.UPDATE &&
            !skippedBackup &&
            failure?.startsWith(NOTHING_TO_ARCHIVE) == true

    companion object {
        /** The agent's stable marker — see [mayUpdateWithoutBackup] */
        const val NOTHING_TO_ARCHIVE = "nothing_to_archive:"
    }
}

internal fun List<String>.appendBounded(line: String, limit: Int = LOG_LINE_LIMIT): List<String> {
    val grown = this + line
    return if (grown.size <= limit) grown else grown.subList(grown.size - limit, grown.size)
}

internal const val LOG_LINE_LIMIT = 2000

internal fun outcomeOf(event: ContainerUpdateEvent): GroupOutcome? = when {
    event.phase != ContainerEventPhase.COMPLETED -> null
    event.didRollBack -> GroupOutcome.RolledBack(event.text)
    event.wasAlreadyCurrent -> GroupOutcome.AlreadyCurrent
    else -> GroupOutcome.Updated
}

internal fun outcomeOf(event: ContainerBackupRunEvent): GroupOutcome? =
    if (event.phase != ContainerEventPhase.COMPLETED) null
    else GroupOutcome.BackedUp(event.archive?.path)

internal fun outcomeOf(event: ContainerRemovalEvent): GroupOutcome? =
    if (event.phase != ContainerEventPhase.COMPLETED) null
    else GroupOutcome.Removed(event.group?.containers?.map { it.name }.orEmpty())
