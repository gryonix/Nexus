package com.skaymer.gryonixnexus.app.shell

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Whether the first-launch tour has been shown */
class AppTourState(private val store: SettingsStore) {
    val hasBeenShown: Boolean get() = store.boolean(KEY) == true

    fun markShown() = store.setBoolean(KEY, true)

    private companion object {
        const val KEY = "appTour.shown"
    }
}

/** Asks the shell to start the tour again */
object AppTourRequests {
    private val _count = MutableStateFlow(0)
    val count: StateFlow<Int> = _count.asStateFlow()

    fun request() {
        _count.value += 1
    }
}
