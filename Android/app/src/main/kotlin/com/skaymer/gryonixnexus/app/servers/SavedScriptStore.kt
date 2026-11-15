package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.servercontrol.SavedScript
import com.skaymer.gryonixnexus.servercontrol.SavedScriptList
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/** Saved scripts, kept on this device */
class SavedScriptStore(private val store: SettingsStore) {
    private val _scripts = MutableStateFlow(read())
    val scripts: StateFlow<List<SavedScript>> = _scripts.asStateFlow()

    fun save(script: SavedScript) = write(SavedScriptList.upserting(script, _scripts.value))

    fun delete(id: String) = write(SavedScriptList.removing(id, _scripts.value))

    private fun write(updated: List<SavedScript>) {
        store.setString(KEY, Json.encodeToString(serializer, updated))
        _scripts.value = updated
    }

    private fun read(): List<SavedScript> =
        store.string(KEY)?.let { runCatching { Json.decodeFromString(serializer, it) }.getOrNull() }.orEmpty()

    private companion object {
        const val KEY = "scripts.v1"
        val serializer = ListSerializer(SavedScript.serializer())
    }
}
