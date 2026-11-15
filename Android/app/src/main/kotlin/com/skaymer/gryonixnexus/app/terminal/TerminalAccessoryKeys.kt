package com.skaymer.gryonixnexus.app.terminal

import com.skaymer.gryonixnexus.app.shell.SettingsStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

enum class KeyGroup { SPECIAL, SYMBOLS, FUNCTION, CONTROL }

/** One key of the row above the keyboard */
data class AccessoryKey(val id: String, val label: String, val group: KeyGroup, val action: Action) {
    sealed interface Action {
        data object ControlToggle : Action
        class Bytes(val bytes: ByteArray) : Action
        class Text(val text: String) : Action
    }
}

object AccessoryCatalog {
    private const val ESC = "\u001B"

    private fun bytes(id: String, label: String, group: KeyGroup, data: ByteArray) =
        AccessoryKey(id, label, group, AccessoryKey.Action.Bytes(data))

    private val special = listOf(
        bytes("esc", "Esc", KeyGroup.SPECIAL, TerminalKeys.ESCAPE),
        bytes("tab", "Tab", KeyGroup.SPECIAL, TerminalKeys.TAB),
        AccessoryKey("ctrl", "Ctrl", KeyGroup.SPECIAL, AccessoryKey.Action.ControlToggle),
        bytes("up", "↑", KeyGroup.SPECIAL, TerminalKeys.UP),
        bytes("down", "↓", KeyGroup.SPECIAL, TerminalKeys.DOWN),
        bytes("left", "←", KeyGroup.SPECIAL, TerminalKeys.LEFT),
        bytes("right", "→", KeyGroup.SPECIAL, TerminalKeys.RIGHT),
        bytes("home", "Home", KeyGroup.SPECIAL, TerminalKeys.HOME),
        bytes("end", "End", KeyGroup.SPECIAL, TerminalKeys.END),
        bytes("pageUp", "PgUp", KeyGroup.SPECIAL, TerminalKeys.PAGE_UP),
        bytes("pageDown", "PgDn", KeyGroup.SPECIAL, TerminalKeys.PAGE_DOWN),
        bytes("enter", "⏎", KeyGroup.SPECIAL, TerminalKeys.ENTER),
        bytes("backspace", "⌫", KeyGroup.SPECIAL, TerminalKeys.BACKSPACE),
    )

    private val symbols = "|~/-_\\`$&*()[]{}<>=+:;\"'@#%^!?.,".map {
        AccessoryKey("sym-$it", it.toString(), KeyGroup.SYMBOLS, AccessoryKey.Action.Text(it.toString()))
    }

    private val function = (1..12).map { number ->
        val tail = if (number <= 4) "O" + (79 + number).toChar()
        else "[" + listOf("15", "17", "18", "19", "20", "21", "23", "24")[number - 5] + "~"
        bytes("f$number", "F$number", KeyGroup.FUNCTION, (ESC + tail).toByteArray())
    }

    private val control = "ACDEKLRUWXZ".map {
        bytes("ctrl-$it", "^$it", KeyGroup.CONTROL, byteArrayOf((it.code - 64).toByte()))
    }

    val all: List<AccessoryKey> = special + symbols + function + control

    fun key(id: String): AccessoryKey? = all.firstOrNull { it.id == id }
}

/** The ordered key ids the user chose, with edits */
@Serializable
data class AccessoryLayout(val ids: List<String> = DEFAULT_IDS) {
    val keys: List<AccessoryKey> get() = ids.mapNotNull(AccessoryCatalog::key)

    fun adding(id: String) =
        if (AccessoryCatalog.key(id) == null || id in ids) this else copy(ids = ids + id)

    fun removing(index: Int) = if (index in ids.indices) copy(ids = ids.filterIndexed { at, _ -> at != index }) else this

    fun moving(from: Int, to: Int): AccessoryLayout {
        if (from !in ids.indices || to !in ids.indices) return this
        val moved = ids.toMutableList()
        moved.add(to, moved.removeAt(from))
        return copy(ids = moved)
    }

    fun reset() = AccessoryLayout()

    companion object {
        val DEFAULT_IDS = listOf(
            "ctrl", "tab", "esc", "up", "down", "left", "right", "sym-|", "sym-~", "sym-/", "sym--",
            "ctrl-C", "ctrl-D", "enter", "backspace",
        )
    }
}

class AccessoryLayoutStore(private val settings: SettingsStore?) {
    private val _layout = MutableStateFlow(load())
    val layout: StateFlow<AccessoryLayout> = _layout.asStateFlow()

    fun load(): AccessoryLayout =
        settings?.string(KEY)?.let { runCatching { JSON.decodeFromString<AccessoryLayout>(it) }.getOrNull() }
            ?: AccessoryLayout()

    fun save(layout: AccessoryLayout) {
        settings?.setString(KEY, JSON.encodeToString(layout))
        _layout.value = layout
    }

    fun update(change: (AccessoryLayout) -> AccessoryLayout) = save(change(_layout.value))

    private companion object {
        const val KEY = "terminal.accessoryKeys"
        val JSON = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    }
}
