package com.skaymer.gryonixnexus.app.shell

import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

interface SettingsStore {
    fun string(key: String): String?
    fun setString(key: String, value: String)
    fun stringList(key: String): List<String>?
    fun setStringList(key: String, value: List<String>)
    fun boolean(key: String): Boolean?
    fun setBoolean(key: String, value: Boolean)
    fun remove(key: String)

    /** Bumped on every write */
    val revision: StateFlow<Long>
}

/** The delimiter for stored lists */
private const val LIST_SEPARATOR = "\n"

/** The Android store */
class PreferencesStore(private val prefs: SharedPreferences) : SettingsStore {
    private val _revision = MutableStateFlow(0L)
    override val revision: StateFlow<Long> = _revision

    private val listener =
        SharedPreferences.OnSharedPreferenceChangeListener { _, _ -> _revision.value++ }

    init {
        prefs.registerOnSharedPreferenceChangeListener(listener)
    }

    override fun string(key: String): String? = prefs.getString(key, null)

    override fun setString(key: String, value: String) {
        prefs.edit().putString(key, value).apply()
    }

    override fun stringList(key: String): List<String>? =
        prefs.getString(key, null)?.let { stored ->
            if (stored.isEmpty()) emptyList() else stored.split(LIST_SEPARATOR)
        }

    override fun setStringList(key: String, value: List<String>) {
        prefs.edit().putString(key, value.joinToString(LIST_SEPARATOR)).apply()
    }

    override fun boolean(key: String): Boolean? =
        if (prefs.contains(key)) prefs.getBoolean(key, false) else null

    override fun setBoolean(key: String, value: Boolean) {
        prefs.edit().putBoolean(key, value).apply()
    }

    override fun remove(key: String) {
        prefs.edit().remove(key).apply()
    }
}
