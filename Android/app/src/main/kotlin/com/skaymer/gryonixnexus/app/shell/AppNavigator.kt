package com.skaymer.gryonixnexus.app.shell

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class AppNavigator {
    private val _openServerID = MutableStateFlow<String?>(null)

    /** The server whose screen is open, if any */
    val openServerID: StateFlow<String?> = _openServerID.asStateFlow()

    fun open(serverID: String) {
        _openServerID.value = serverID
    }

    fun closeServer() {
        _openServerID.value = null
    }

    private val _openSection = MutableStateFlow<AppTab?>(null)

    val openSection: StateFlow<AppTab?> = _openSection.asStateFlow()

    fun show(tab: AppTab) {
        _openSection.value = tab
    }

    fun sectionShown() {
        _openSection.value = null
    }
}
