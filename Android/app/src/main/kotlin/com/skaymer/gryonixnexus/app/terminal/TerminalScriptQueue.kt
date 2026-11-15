package com.skaymer.gryonixnexus.app.terminal

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** Script text waiting for a server's terminal */
object TerminalScriptQueue {
    private val _pending = MutableStateFlow<Map<String, ByteArray>>(emptyMap())
    val pending: StateFlow<Map<String, ByteArray>> = _pending.asStateFlow()

    fun queue(deploymentID: String, text: String) = _pending.update { it + (deploymentID to text.toByteArray()) }

    fun take(deploymentID: String): ByteArray? {
        val found = _pending.value[deploymentID] ?: return null
        _pending.update { it - deploymentID }
        return found
    }
}
