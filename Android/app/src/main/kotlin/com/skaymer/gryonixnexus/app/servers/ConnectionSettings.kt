package com.skaymer.gryonixnexus.app.servers

import android.icu.text.MeasureFormat
import android.icu.util.Measure
import android.icu.util.MeasureUnit
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import java.util.Locale

/** When a card says No connection, and when it reconnects */
data class ConnectionWaits(val silenceSeconds: Int = 15, val reconnectSeconds: Int? = 90) {
    /** Wait for the very first answer */
    val firstAnswerSeconds: Int get() = maxOf(45, silenceSeconds)

    /** Silence before the session is rebuilt, or null when off */
    val rebuildSeconds: Int? get() = reconnectSeconds?.let { maxOf(it, silenceSeconds * 2) }
}

/** The user's choice of connection waits */
object ConnectionSettings {
    const val SILENCE_KEY = "connection.silence"
    const val RECONNECT_KEY = "connection.reconnect"
    const val DEFAULT_SILENCE = 15
    const val DEFAULT_RECONNECT = 90
    val SILENCES = listOf(15, 30, 60, 120, 300)
    val SILENCE_RANGE = 5..3600
    /** Zero turns reconnecting off */
    val RECONNECTS = listOf(60, 90, 180, 300, 600, 0)
    val RECONNECT_RANGE = 30..86400

    fun silence(store: SettingsStore): Int =
        store.string(SILENCE_KEY)?.toIntOrNull()?.takeIf { it in SILENCE_RANGE } ?: DEFAULT_SILENCE

    fun reconnect(store: SettingsStore): Int =
        store.string(RECONNECT_KEY)?.toIntOrNull()?.takeIf { it == 0 || it in RECONNECT_RANGE } ?: DEFAULT_RECONNECT

    /** Hours, minutes and seconds, e.g. 1 minute 30 seconds */
    fun title(seconds: Int, locale: Locale = Locale.getDefault()): String {
        val parts = listOf(
            seconds / 3600 to MeasureUnit.HOUR,
            seconds % 3600 / 60 to MeasureUnit.MINUTE,
            seconds % 60 to MeasureUnit.SECOND,
        ).filter { it.first > 0 }.map { Measure(it.first, it.second) }
        if (parts.isEmpty()) return MeasureFormat.getInstance(locale, MeasureFormat.FormatWidth.WIDE)
            .format(Measure(0, MeasureUnit.SECOND))
        return MeasureFormat.getInstance(locale, MeasureFormat.FormatWidth.WIDE).formatMeasures(*parts.toTypedArray())
    }

    fun waits(store: SettingsStore): ConnectionWaits =
        ConnectionWaits(silence(store), reconnect(store).takeIf { it > 0 })
}

/** Marks quiet servers, and when to rebuild their session */
class SilenceWatch(
    val waits: () -> ConnectionWaits,
    /** The card's text for the given seconds of silence */
    val reason: (Int) -> String,
)
