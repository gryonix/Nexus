package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.app.shell.SettingsStore
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** The terminal sessions kept across app restarts, in order */
@Serializable
data class SavedTerminalSession(
    val profileID: String,
    val deploymentID: String,
    val nodeID: String? = null,
    val username: String,
)

@Serializable
data class SavedTerminalSessions(
    val records: List<SavedTerminalSession> = emptyList(),
    val selected: String? = null,
) {
    fun open(record: SavedTerminalSession): SavedTerminalSessions {
        val kept = if (records.any { it.profileID == record.profileID }) {
            records.map { if (it.profileID == record.profileID) record else it }
        } else {
            records + record
        }
        return copy(records = kept, selected = record.profileID)
    }

    fun select(profileID: String): SavedTerminalSessions =
        if (records.any { it.profileID == profileID }) copy(selected = profileID) else this

    fun close(profileID: String): SavedTerminalSessions {
        val kept = records.filter { it.profileID != profileID }
        return copy(records = kept, selected = if (selected == profileID) kept.lastOrNull()?.profileID else selected)
    }

    fun closeAll(deploymentID: String): SavedTerminalSessions {
        val kept = records.filter { it.deploymentID != deploymentID }
        val stillThere = kept.any { it.profileID == selected }
        return copy(records = kept, selected = if (stillThere) selected else kept.lastOrNull()?.profileID)
    }

    val selectedRecord: SavedTerminalSession? get() = records.firstOrNull { it.profileID == selected }

    /** The session to bring back for one server */
    fun restorable(deploymentID: String): SavedTerminalSession? =
        selectedRecord?.takeIf { it.deploymentID == deploymentID }
            ?: records.lastOrNull { it.deploymentID == deploymentID }
}

/** Device-only storage for the saved sessions */
class SavedTerminalSessionsStore(private val settings: SettingsStore) {
    fun load(): SavedTerminalSessions =
        settings.string(KEY)?.let { runCatching { JSON.decodeFromString<SavedTerminalSessions>(it) }.getOrNull() }
            ?: SavedTerminalSessions()

    fun save(sessions: SavedTerminalSessions) = settings.setString(KEY, JSON.encodeToString(sessions))

    fun update(change: (SavedTerminalSessions) -> SavedTerminalSessions) = save(change(load()))

    private companion object {
        const val KEY = "terminal.savedSessions"
        val JSON = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    }
}

object TerminalTmux {
    /** The command that joins or creates the profile's tmux session */
    fun launchCommand(profileID: String): String {
        val name = "gryonix-" + profileID.take(8).lowercase()
        return "command -v tmux >/dev/null 2>&1 && exec tmux new -A -s $name\r"
    }
}
