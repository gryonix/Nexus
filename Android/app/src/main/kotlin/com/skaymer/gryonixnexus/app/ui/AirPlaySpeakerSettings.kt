package com.skaymer.gryonixnexus.app.ui

import androidx.annotation.StringRes
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.catalog.services.ShairportSyncOptions

/** How one speaker option appears on screen */
data class SpeakerSetting(
    val key: String,
    @StringRes val title: Int,
    @StringRes val info: Int,
    val control: Control,
    val limits: ClosedFloatingPointRange<Double>? = null,
) {
    sealed class Control {
        data class Choice(val choices: List<Pair<String, Int>>) : Control()
        data class Number(val standard: Double, val step: Double, val unit: String) : Control()
        data class Buffer(val minimal: Double, val standard: Double, val step: Double, val unit: String) : Control()
        data object Toggle : Control()
    }

    /** Lowest and highest value the file accepts */
    val range: ClosedFloatingPointRange<Double>
        get() = limits ?: (ShairportSyncOptions.options.firstOrNull { it.key == key }?.kind as? ShairportSyncOptions.Kind.Number)
            ?.let { it.low..it.high } ?: 0.0..0.0
}

/** The speaker's options, grouped as the screen shows them */
object SpeakerSettingsCatalog {
    private val auto = "auto" to R.string.speaker_choice_auto

    val sound = listOf(
        SpeakerSetting("ignore_volume_control", R.string.speaker_ignore_volume, R.string.speaker_info_ignore_volume, SpeakerSetting.Control.Toggle),
        SpeakerSetting("default_airplay_volume", R.string.speaker_start_volume, R.string.speaker_info_start_volume, SpeakerSetting.Control.Number(-24.0, 1.0, "dB")),
        SpeakerSetting("volume_range_db", R.string.speaker_volume_range, R.string.speaker_info_volume_range, SpeakerSetting.Control.Number(60.0, 5.0, "dB")),
        SpeakerSetting("volume_max_db", R.string.speaker_volume_max, R.string.speaker_info_volume_max, SpeakerSetting.Control.Number(0.0, 1.0, "dB")),
    )

    val hdmiVolume = listOf(
        SpeakerSetting("cec_volume", R.string.speaker_hdmi_volume, R.string.speaker_info_hdmi_volume, SpeakerSetting.Control.Toggle),
        SpeakerSetting("cec_volume_min", R.string.speaker_hdmi_lowest, R.string.speaker_info_hdmi_lowest, SpeakerSetting.Control.Number(1.0, 1.0, "")),
        SpeakerSetting("cec_volume_max", R.string.speaker_hdmi_highest, R.string.speaker_info_hdmi_highest, SpeakerSetting.Control.Number(40.0, 1.0, "")),
        SpeakerSetting("cec_tv_wakes", R.string.speaker_hdmi_tv_wakes, R.string.speaker_info_hdmi_tv_wakes, SpeakerSetting.Control.Toggle),
        SpeakerSetting("cec_tv_wait", R.string.speaker_hdmi_tv_wait, R.string.speaker_info_hdmi_tv_wait, SpeakerSetting.Control.Number(60.0, 5.0, "s")),
        SpeakerSetting("cec_keep_connected", R.string.speaker_hdmi_keep, R.string.speaker_info_hdmi_keep, SpeakerSetting.Control.Toggle),
        SpeakerSetting("cec_off_delay", R.string.speaker_hdmi_off_delay, R.string.speaker_info_hdmi_off_delay, SpeakerSetting.Control.Number(2.0, 1.0, "s")),
        SpeakerSetting("cec_grace", R.string.speaker_hdmi_grace, R.string.speaker_info_hdmi_grace, SpeakerSetting.Control.Number(15.0, 1.0, "s")),
    )

    val timing = listOf(
        SpeakerSetting("audio_backend_latency_offset_in_seconds", R.string.speaker_delay, R.string.speaker_info_delay, SpeakerSetting.Control.Number(0.0, 0.01, "s")),
        SpeakerSetting("audio_backend_buffer_desired_length_in_seconds", R.string.speaker_buffer, R.string.speaker_info_buffer, SpeakerSetting.Control.Buffer(0.03, 0.2, 0.01, "s")),
        SpeakerSetting("drift_tolerance_in_seconds", R.string.speaker_drift, R.string.speaker_info_drift, SpeakerSetting.Control.Number(0.002, 0.001, "s")),
        SpeakerSetting("interpolation", R.string.speaker_resampling, R.string.speaker_info_resampling, SpeakerSetting.Control.Choice(listOf(
            auto, "basic" to R.string.speaker_choice_basic, "soxr" to R.string.speaker_choice_soxr,
        ))),
    )

    val format = listOf(
        SpeakerSetting("output_rate", R.string.speaker_rate, R.string.speaker_info_rate, SpeakerSetting.Control.Choice(listOf(
            auto, "44100" to R.string.speaker_rate_44, "88200" to R.string.speaker_rate_88,
            "176400" to R.string.speaker_rate_176, "352800" to R.string.speaker_rate_352,
        ))),
        SpeakerSetting("output_format", R.string.speaker_format, R.string.speaker_info_format, SpeakerSetting.Control.Choice(listOf(
            auto, "S16" to R.string.speaker_format_16, "S16_LE" to R.string.speaker_format_16le,
            "S24" to R.string.speaker_format_24, "S24_3LE" to R.string.speaker_format_24packed,
            "S32" to R.string.speaker_format_32,
        ))),
        SpeakerSetting("disable_standby_mode", R.string.speaker_awake, R.string.speaker_info_awake, SpeakerSetting.Control.Choice(listOf(
            "never" to R.string.speaker_awake_never, "auto" to R.string.speaker_awake_connected,
            "always" to R.string.speaker_awake_always,
        ))),
        SpeakerSetting("disable_synchronization", R.string.speaker_no_sync, R.string.speaker_info_no_sync, SpeakerSetting.Control.Toggle),
    )

    val sessions = listOf(
        SpeakerSetting("allow_session_interruption", R.string.speaker_takeover, R.string.speaker_info_takeover, SpeakerSetting.Control.Toggle),
        SpeakerSetting("session_timeout", R.string.speaker_timeout, R.string.speaker_info_timeout, SpeakerSetting.Control.Number(120.0, 10.0, "s")),
    )

    /** Every step on the wheel, the standard one left empty */
    fun wheelValues(low: Double, high: Double, step: Double, standard: String, stored: String): List<String> {
        val count = if (step > 0 && high >= low) Math.round((high - low) / step).toInt() else 0
        val all = (0..count).map { plain(low + it * step) }.map { if (it == standard) "" else it }.toMutableList()
        if ("" !in all) all += ""
        val chosen = if (stored == standard) "" else stored
        if (chosen !in all) all += chosen
        val standardNumber = standard.toDoubleOrNull() ?: 0.0
        return all.sortedBy { it.toDoubleOrNull() ?: standardNumber }
    }

    /** A plain decimal the config accepts, without trailing zeros */
    fun plain(number: Double): String {
        var text = String.format(java.util.Locale.ROOT, "%.3f", number).trimEnd('0').trimEnd('.')
        if (text == "-0") text = "0"
        return text
    }
}
