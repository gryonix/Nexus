package com.skaymer.gryonixnexus.app.terminal

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Open shells by login, kept while the app runs. */
class TerminalShells(
    private val scopeFactory: () -> CoroutineScope = { CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) },
) {
    /** One open shell, shown as a tab */
    class Shell(
        val profileID: String,
        val deploymentID: String,
        val title: String,
        val terminal: TerminalViewModel,
    )

    private val scope by lazy { scopeFactory() }
    private val _open = MutableStateFlow<List<Shell>>(emptyList())
    val open: StateFlow<List<Shell>> = _open.asStateFlow()

    fun shell(profileID: String): Shell? = _open.value.firstOrNull { it.profileID == profileID }

    fun of(deploymentID: String): List<Shell> = _open.value.filter { it.deploymentID == deploymentID }

    /** The open shell, or a new one and true */
    fun obtain(
        profileID: String,
        deploymentID: String,
        title: String,
        make: (CoroutineScope) -> TerminalViewModel,
    ): Pair<Shell, Boolean> {
        shell(profileID)?.let { return it to false }
        val made = Shell(profileID, deploymentID, title, make(scope))
        _open.value = _open.value + made
        return made to true
    }

    fun close(profileID: String) {
        shell(profileID)?.terminal?.close()
        _open.value = _open.value.filter { it.profileID != profileID }
    }
}

/** Which tabs come back for one server after a restart */
object TerminalRestore {
    /** Saved logins still known; the rest are dropped */
    fun plan(
        saved: SavedTerminalSessions,
        deploymentID: String,
        known: List<TerminalProfile>,
    ): Pair<List<TerminalProfile>, String?> {
        val records = saved.records.filter { it.deploymentID == deploymentID }
        val back = records.mapNotNull { record -> known.firstOrNull { it.id == record.profileID } }
        val shown = saved.restorable(deploymentID)?.profileID?.takeIf { id -> back.any { it.id == id } }
        return back to (shown ?: back.lastOrNull()?.id)
    }
}
