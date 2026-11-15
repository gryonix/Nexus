package com.skaymer.gryonixnexus.app.shell

import com.skaymer.gryonixnexus.app.notify.AlertCard
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

    var openedOnlyServer = false

    fun closeServer() {
        _openServerID.value = null
    }

    private val _askedSection = MutableStateFlow<Pair<String, ServerSection>?>(null)

    val askedSection: StateFlow<Pair<String, ServerSection>?> = _askedSection.asStateFlow()

    private var askedService: Pair<String, String>? = null

    /** The service whose log a server should open */
    fun takeService(serverID: String): String? {
        val asked = askedService?.takeIf { it.first == serverID } ?: return null
        askedService = null
        return asked.second
    }

    private var askedAlert: Pair<String, AlertCard>? = null

    /** The alert a server should show */
    fun takeAlert(serverID: String): AlertCard? {
        val asked = askedAlert?.takeIf { it.first == serverID } ?: return null
        askedAlert = null
        return asked.second
    }

    fun open(serverID: String, section: ServerSection, service: String? = null, card: AlertCard? = null) {
        askedAlert = card?.let { serverID to it }
        askedService = service?.takeIf { card == null }?.let { serverID to it }
        _askedSection.value = serverID to section
        _openServerID.value = serverID
    }

    fun takeSection(serverID: String): ServerSection? {
        val asked = _askedSection.value?.takeIf { it.first == serverID } ?: return null
        _askedSection.value = null
        return asked.second
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
