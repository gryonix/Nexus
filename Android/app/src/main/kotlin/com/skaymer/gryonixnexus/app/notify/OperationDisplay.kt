package com.skaymer.gryonixnexus.app.notify

import com.skaymer.gryonixnexus.agentcontrol.AgentJobKind
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.servercontrol.DetachedJobs

/** Kinds of operation a notification can belong to */
enum class OperationKind {
    INSTALL, UPDATE, BACKUP, RESTORE, MOVE, REMOVAL, OTHER;

    val storageKey: String get() = "$KIND_PREFIX${name.lowercase()}"

    companion object {
        private const val KIND_PREFIX = "notice.kind."

        fun of(kind: AgentJobKind): OperationKind = when (kind) {
            AgentJobKind.INSTALL, AgentJobKind.REPAIR, AgentJobKind.REINSTALL -> INSTALL
            AgentJobKind.UPDATE, AgentJobKind.CONTAINER_UPDATE, AgentJobKind.AGENT_UPDATE -> UPDATE
            AgentJobKind.BACKUP, AgentJobKind.CONTAINER_BACKUP -> BACKUP
            AgentJobKind.RESTORE -> RESTORE
            AgentJobKind.MOVE -> MOVE
            AgentJobKind.UNINSTALL, AgentJobKind.CONTAINER_REMOVAL -> REMOVAL
            else -> OTHER
        }

        fun of(kind: DetachedJobs.Kind): OperationKind = when (kind) {
            DetachedJobs.Kind.UPDATE -> UPDATE
            DetachedJobs.Kind.BACKUP -> BACKUP
            DetachedJobs.Kind.RESTORE -> RESTORE
            DetachedJobs.Kind.UNINSTALL -> REMOVAL
            DetachedJobs.Kind.CONTROL -> OTHER
        }
    }
}

/** Which running operations show as notifications */
data class OperationDisplay(
    val enabled: Boolean = true,
    val hidden: Set<OperationKind> = emptySet(),
) {
    fun shows(kind: OperationKind): Boolean = enabled && kind !in hidden

    fun withKind(kind: OperationKind, shown: Boolean): OperationDisplay =
        copy(hidden = if (shown) hidden - kind else hidden + kind)

    fun save(store: SettingsStore) {
        store.setBoolean(ENABLED, enabled)
        OperationKind.entries.forEach { store.setBoolean(it.storageKey, it !in hidden) }
    }

    companion object {
        const val ENABLED = "notice.operations"

        fun load(store: SettingsStore): OperationDisplay = OperationDisplay(
            enabled = store.boolean(ENABLED) ?: true,
            hidden = OperationKind.entries.filter { store.boolean(it.storageKey) == false }.toSet(),
        )
    }
}
