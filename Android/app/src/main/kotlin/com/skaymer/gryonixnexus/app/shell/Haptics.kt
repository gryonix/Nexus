package com.skaymer.gryonixnexus.app.shell

import android.os.Build
import android.view.HapticFeedbackConstants

object Haptics {
    /** The same key the other app writes */
    const val KEY = "haptics.enabled"

    fun isEnabled(stored: Boolean?): Boolean = stored ?: true

    /** What a moment feels like */
    enum class Feel {
        /** An ordinary button */
        TAP,

        /** A button that destroys something */
        WEIGHTY,

        SUCCESS,
        FAILURE,
    }

    fun constant(feel: Feel, sdk: Int = Build.VERSION.SDK_INT): Int = when (feel) {
        Feel.TAP -> HapticFeedbackConstants.VIRTUAL_KEY
        Feel.WEIGHTY -> HapticFeedbackConstants.LONG_PRESS
        Feel.SUCCESS ->
            if (sdk >= Build.VERSION_CODES.R) HapticFeedbackConstants.CONFIRM
            else HapticFeedbackConstants.VIRTUAL_KEY
        Feel.FAILURE ->
            if (sdk >= Build.VERSION_CODES.R) HapticFeedbackConstants.REJECT
            else HapticFeedbackConstants.LONG_PRESS
    }
}

/** Whether the device answers a press */
fun SettingsStore.hapticsEnabled(): Boolean = Haptics.isEnabled(boolean(Haptics.KEY))

fun SettingsStore.setHapticsEnabled(value: Boolean) = setBoolean(Haptics.KEY, value)
