package com.skaymer.gryonixnexus.app.shell

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** A store of its own for each test */
class InMemorySettingsStore : SettingsStore {
    private val values = mutableMapOf<String, Any>()
    private val _revision = MutableStateFlow(0L)
    override val revision: StateFlow<Long> = _revision

    override fun string(key: String): String? = values[key] as? String

    override fun setString(key: String, value: String) {
        values[key] = value
        _revision.value++
    }

    @Suppress("UNCHECKED_CAST")
    override fun stringList(key: String): List<String>? = values[key] as? List<String>

    override fun setStringList(key: String, value: List<String>) {
        values[key] = value
        _revision.value++
    }

    override fun boolean(key: String): Boolean? = values[key] as? Boolean

    override fun setBoolean(key: String, value: Boolean) {
        values[key] = value
        _revision.value++
    }

    override fun remove(key: String) {
        values.remove(key)
        _revision.value++
    }
}
