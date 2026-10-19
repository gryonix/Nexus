package com.skaymer.gryonixnexus.app.shell

/** Whether the welcome has been shown */
class WelcomeState(private val store: SettingsStore) {
    val hasBeenShown: Boolean get() = store.boolean(KEY) == true

    fun markShown() = store.setBoolean(KEY, true)

    fun forget() = store.remove(KEY)

    private companion object {
        const val KEY = "welcome.shown"
    }
}
