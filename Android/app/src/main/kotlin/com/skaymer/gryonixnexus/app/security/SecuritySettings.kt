package com.skaymer.gryonixnexus.app.security

import com.skaymer.gryonixnexus.app.shell.SettingsStore
import kotlinx.coroutines.launch

enum class GatedAction {
    /** Opening the screen that lists a server's sign-in details */
    ACCESS_SCREEN,

    /** Revealing or copying ONE saved password */
    REVEAL,

    EXPORT,
}

class SecuritySettings(private val store: SettingsStore) {
    object Keys {
        const val ACCESS_SCREEN = "security.gateAccessScreen"
        const val REVEAL = "security.gateReveal"
        const val EXPORT = "security.gateExport"
    }

    fun isGated(action: GatedAction): Boolean =
        store.string(key(action)) != OFF

    fun setGated(gated: Boolean, action: GatedAction) {
        store.setString(key(action), if (gated) ON else OFF)
    }

    companion object {
        private const val ON = "true"
        private const val OFF = "false"

        fun key(action: GatedAction): String = when (action) {
            GatedAction.ACCESS_SCREEN -> Keys.ACCESS_SCREEN
            GatedAction.REVEAL -> Keys.REVEAL
            GatedAction.EXPORT -> Keys.EXPORT
        }
    }
}

fun interface DeviceGate {
    suspend fun confirm(reason: String): Boolean
}

val LocalDeviceGate = androidx.compose.runtime.staticCompositionLocalOf<DeviceGate> {
    DeviceGate { false }
}

val LocalSecuritySettings =
    androidx.compose.runtime.staticCompositionLocalOf<SecuritySettings?> { null }

@androidx.compose.runtime.Composable
fun rememberGuard(): (GatedAction, String, () -> Unit) -> Unit {
    val gate = LocalDeviceGate.current
    val settings = LocalSecuritySettings.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    return { action, reason, body ->
        if (settings?.isGated(action) != true) {
            body()
        } else {
            scope.launch {
                if (gate.confirm(reason)) body()
            }
        }
    }
}
