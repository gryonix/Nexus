package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.servercontrol.AudioHubSources

/** Settings of the hub's Spotify, AirPlay and music library players */
@Composable
internal fun AudioHubSourcesSections(saved: AudioHubSources, draft: AudioHubSources, edit: (AudioHubSources) -> Unit) {
    if (saved.hasSpotify) {
        PlayerSection("spotify", "Spotify", stringResource(R.string.audio_hub_spotify_note), AudioHubPlayerCatalog.spotify, saved, draft, edit)
    }
    if (saved.hasAirPlay) {
        PlayerSection("airplay", "AirPlay", stringResource(R.string.audio_hub_airplay_note), AudioHubPlayerCatalog.airPlay, saved, draft, edit)
    }
    if (saved.hasLibrary) {
        PlayerSection("mpd", "MPD", stringResource(R.string.audio_hub_library_note), AudioHubPlayerCatalog.library, saved, draft, edit)
    }
}

@Composable
private fun PlayerSection(
    prefix: String,
    header: String,
    note: String,
    rows: List<SpeakerSetting>,
    saved: AudioHubSources,
    draft: AudioHubSources,
    edit: (AudioHubSources) -> Unit,
) {
    val lead = "$prefix."
    val values = draft.values.filterKeys { it.startsWith(lead) }.mapKeys { it.key.removePrefix(lead) }
    GroupedSection(header = header, note = note) {
        FieldRow(
            label = stringResource(R.string.airplay_name), value = draft.values["${lead}name"].orEmpty(),
            onValueChange = { edit(draft.with("${lead}name", it)) },
            placeholder = saved.values["${lead}name"].orEmpty(),
        )
        rows.forEachIndexed { index, setting ->
            SettingRow(setting, values, index < rows.lastIndex) { fresh ->
                edit(AudioHubSources(draft.values + fresh.mapKeys { lead + it.key }))
            }
        }
    }
}
