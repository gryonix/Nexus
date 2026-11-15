package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.SpeakerSetting.Control

/** The hub players' options, keyed as the agent names them */
object AudioHubPlayerCatalog {
    val spotify = listOf(
        SpeakerSetting("bitrate", R.string.audio_hub_quality, R.string.audio_hub_quality_info, Control.Choice(listOf(
            "96" to R.string.audio_hub_kbit_96, "160" to R.string.audio_hub_kbit_160, "320" to R.string.audio_hub_kbit_320,
        ))),
        SpeakerSetting("volume", R.string.speaker_start_volume, R.string.audio_hub_start_volume_info,
            Control.Number(90.0, 5.0, "%"), 0.0..100.0),
        SpeakerSetting("normalise", R.string.audio_hub_even_volume, R.string.audio_hub_even_volume_info, Control.Toggle),
        SpeakerSetting("pregain", R.string.audio_hub_pregain, R.string.audio_hub_pregain_info,
            Control.Number(0.0, 1.0, "dB"), -10.0..10.0),
        SpeakerSetting("volume_controller", R.string.audio_hub_volume_control, R.string.audio_hub_volume_control_info, Control.Choice(listOf(
            "softvol" to R.string.audio_hub_volume_in_spotify, "none" to R.string.audio_hub_volume_fixed,
        ))),
        SpeakerSetting("device_type", R.string.audio_hub_device_type, R.string.audio_hub_device_type_info, Control.Choice(listOf(
            "speaker" to R.string.audio_hub_type_speaker, "avr" to R.string.audio_hub_type_avr,
            "tv" to R.string.audio_hub_type_tv, "computer" to R.string.audio_hub_type_computer,
            "stb" to R.string.audio_hub_type_stb, "audiodongle" to R.string.audio_hub_type_dongle,
        ))),
        SpeakerSetting("autoplay", R.string.audio_hub_autoplay, R.string.audio_hub_autoplay_info, Control.Toggle),
    )

    val airPlay = SpeakerSettingsCatalog.sound + SpeakerSettingsCatalog.timing + SpeakerSettingsCatalog.sessions

    val library = listOf(
        SpeakerSetting("replaygain", R.string.audio_hub_even_volume, R.string.audio_hub_replaygain_info, Control.Choice(listOf(
            "off" to R.string.audio_hub_replaygain_off, "track" to R.string.audio_hub_replaygain_track,
            "album" to R.string.audio_hub_replaygain_album, "auto" to R.string.speaker_choice_auto,
        ))),
        SpeakerSetting("auto_update", R.string.audio_hub_auto_update, R.string.audio_hub_auto_update_info, Control.Toggle),
    )
}
