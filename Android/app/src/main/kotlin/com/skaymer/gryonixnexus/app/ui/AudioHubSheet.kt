package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.LoadingRow
import com.skaymer.gryonixnexus.app.ui.design.MenuValueRow
import com.skaymer.gryonixnexus.app.ui.design.PendingChangesBar
import com.skaymer.gryonixnexus.app.ui.design.PendingChangesText
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.servercontrol.AudioHubParser
import com.skaymer.gryonixnexus.servercontrol.AudioHubSources
import com.skaymer.gryonixnexus.servercontrol.AudioHubState
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.launch

/** Calls one odio-api path on a deployment */
private typealias OdioCall = suspend (Deployment, String, String, String) -> String

/** Opens the hub's remote control */
@Composable
fun AudioHubRow(deployment: Deployment, odio: OdioCall) {
    var open by remember { mutableStateOf(false) }
    ValueRow(stringResource(R.string.audio_hub_controls), null, { open = true })
    if (open) AudioHubSheet(deployment, odio) { open = false }
}

private suspend fun fetchHub(deployment: Deployment, odio: OdioCall): AudioHubState {
    var state = AudioHubParser.withServer(odio(deployment, "GET", "/audio/server", ""), AudioHubState())
    state = state.copy(
        outputs = AudioHubParser.outputs(odio(deployment, "GET", "/audio/outputs", "")),
        players = AudioHubParser.players(odio(deployment, "GET", "/players", "")),
        services = AudioHubParser.services(odio(deployment, "GET", "/services", "")),
    )
    val bluetooth = runCatching { odio(deployment, "GET", "/bluetooth", "") }.getOrNull()
    return bluetooth?.let { AudioHubParser.withBluetooth(it, state) } ?: state
}

/** Remote control for the odio audio hub */
@Composable
fun AudioHubSheet(deployment: Deployment, odio: OdioCall, onClose: () -> Unit) {
    var state by remember { mutableStateOf<AudioHubState?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var tick by remember { mutableStateOf(0) }
    val scope = rememberCoroutineScope()
    var sources by remember { mutableStateOf(AudioHubSources()) }
    var sourcesDraft by remember { mutableStateOf(AudioHubSources()) }
    LaunchedEffect(deployment.id, tick) {
        runCatching { fetchHub(deployment, odio) }
            .onSuccess { state = it; error = null }.onFailure { error = it.message ?: it.toString() }
        if (sourcesDraft == sources) {
            runCatching { odio(deployment, "GET", AudioHubSources.PATH, "") }
                .onSuccess { sources = AudioHubSources.parse(it); sourcesDraft = sources }
        }
    }
    val run: (String, String) -> Unit = { path, body ->
        scope.launch {
            runCatching { odio(deployment, "POST", path, body) }
                .onSuccess { tick++ }.onFailure { error = it.message ?: it.toString() }
        }
    }
    var draft by remember { mutableStateOf(AudioHubDraft()) }
    val apply: () -> Unit = {
        val calls = state?.let { draft.calls(it) }.orEmpty()
        scope.launch {
            runCatching {
                calls.forEach { odio(deployment, "POST", it, "") }
                sourcesDraft.changes(sources)?.let { changed ->
                    sources = AudioHubSources.parse(odio(deployment, "POST", AudioHubSources.PATH, changed))
                    sourcesDraft = sources
                }
            }.onSuccess { draft = AudioHubDraft(); tick++ }.onFailure { error = it.message ?: it.toString() }
        }
    }
    IOSSheet(title = stringResource(R.string.audio_hub_title), onClose = onClose, closeLabel = stringResource(R.string.close)) {
        error?.let { GroupedSection { Text(it, color = Gryonix.colors.danger, modifier = Modifier.padding(Metrics.listInset)) } }
        val current = state
        if (current == null) {
            if (error == null) GroupedSection { LoadingRow() }
        } else {
            AudioHubVolume(current, draft, { draft = it }, run)
            AudioHubPlayers(current.players, run)
            AudioHubServices(current.services, draft) { draft = it }
            AudioHubBluetooth(current, draft, { draft = it }, run)
            AudioHubSourcesSections(sources, sourcesDraft) { sourcesDraft = it }
            AudioHubPendingBar(draft.calls(current).isNotEmpty() || sourcesDraft.changes(sources) != null, apply) {
                draft = AudioHubDraft()
                sourcesDraft = sources
            }
        }
    }
}

/** Hub settings that wait to be applied */
internal data class AudioHubDraft(
    val output: String? = null,
    val players: Map<String, Boolean> = emptyMap(),
    val bluetooth: Boolean? = null,
) {
    /** The hub calls that make the state match */
    fun calls(state: AudioHubState): List<String> = buildList {
        val current = state.outputs.firstOrNull { it.isDefault }?.name
        if (output != null && output != current) add("/audio/outputs/$output/default")
        state.services.forEach { service ->
            val on = players[service.unit] ?: return@forEach
            if (on != service.running) add("/services/user/${service.unit}/${if (on) "start" else "stop"}")
        }
        if (bluetooth != null && bluetooth != state.bluetoothPowered) {
            add(if (bluetooth) "/bluetooth/power_up" else "/bluetooth/power_down")
        }
    }
}

/** The bar of unapplied hub settings */
@Composable
private fun AudioHubPendingBar(visible: Boolean, onApply: () -> Unit, onRevert: () -> Unit) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), contentAlignment = Alignment.Center) {
        PendingChangesBar(
            visible = visible,
            text = PendingChangesText(stringResource(R.string.airplay_apply), "", stringResource(R.string.pending_changes_cancel)),
            onApply = onApply,
            onRevert = onRevert,
        )
    }
}

@Composable
private fun AudioHubVolume(
    state: AudioHubState,
    draft: AudioHubDraft,
    edit: (AudioHubDraft) -> Unit,
    run: (String, String) -> Unit,
) {
    var volume by remember(state.volume) { mutableFloatStateOf(state.volume.toFloat()) }
    GroupedSection(header = stringResource(R.string.audio_hub_volume), note = stringResource(R.string.audio_hub_volume_note)) {
        Column(Modifier.padding(horizontal = Metrics.listInset, vertical = 8.dp)) {
            Text("${AudioHubState.percent(volume.toDouble())}%", color = Gryonix.colors.secondaryLabel)
            Slider(
                value = volume,
                onValueChange = { volume = it },
                onValueChangeFinished = { run("/audio/server/volume", AudioHubParser.volumeBody(volume.toDouble())) },
            )
        }
        ToggleRow(stringResource(R.string.audio_hub_mute), state.muted, { run("/audio/server/mute", "") },
            showDivider = state.outputs.size > 1)
        if (state.outputs.size > 1) {
            val chosen = state.outputs.firstOrNull { it.name == draft.output } ?: state.outputs.firstOrNull { it.isDefault }
            MenuValueRow(stringResource(R.string.audio_hub_output), chosen?.title.orEmpty(), showDivider = false) { close ->
                state.outputs.forEach { output ->
                    DropdownMenuItem(text = { Text(output.title) }, onClick = {
                        close(); edit(draft.copy(output = output.name))
                    })
                }
            }
        }
    }
}

@Composable
private fun AudioHubPlayers(players: List<AudioHubState.Player>, run: (String, String) -> Unit) {
    GroupedSection(header = stringResource(R.string.audio_hub_now_playing)) {
        if (players.isEmpty()) {
            Text(stringResource(R.string.audio_hub_nothing_playing), color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(Metrics.listInset))
        }
        players.forEach { player -> AudioHubPlayer(player, run) }
    }
}

@Composable
private fun AudioHubPlayer(player: AudioHubState.Player, run: (String, String) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = Metrics.listInset, vertical = 8.dp)) {
        Text(player.identity, style = MaterialTheme.typography.labelMedium, color = Gryonix.colors.secondaryLabel)
        Text(player.title.ifEmpty { "—" }, style = MaterialTheme.typography.titleMedium)
        if (player.artist.isNotEmpty()) Text(player.artist, color = Gryonix.colors.secondaryLabel)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
            TransportButton(Icons.Filled.SkipPrevious, R.string.audio_hub_previous, player.canGoPrevious) {
                run("/players/${player.busName}/previous", "")
            }
            val playing = player.isPlaying
            TransportButton(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                if (playing) R.string.audio_hub_pause else R.string.audio_hub_play, true) {
                run("/players/${player.busName}/play_pause", "")
            }
            TransportButton(Icons.Filled.SkipNext, R.string.audio_hub_next, player.canGoNext) {
                run("/players/${player.busName}/next", "")
            }
        }
    }
}

@Composable
private fun TransportButton(icon: ImageVector, label: Int, enabled: Boolean, onClick: () -> Unit) {
    IconButton(onClick = onClick, enabled = enabled) { Icon(icon, contentDescription = stringResource(label)) }
}

@Composable
private fun AudioHubServices(services: List<AudioHubState.Service>, draft: AudioHubDraft, edit: (AudioHubDraft) -> Unit) {
    if (services.isEmpty()) return
    GroupedSection(header = stringResource(R.string.audio_hub_players), note = stringResource(R.string.audio_hub_players_note)) {
        services.forEachIndexed { index, service ->
            ToggleRow(service.title, draft.players[service.unit] ?: service.running, { on ->
                edit(draft.copy(players = draft.players + (service.unit to on)))
            }, showDivider = index < services.lastIndex)
        }
    }
}

@Composable
private fun AudioHubBluetooth(
    state: AudioHubState,
    draft: AudioHubDraft,
    edit: (AudioHubDraft) -> Unit,
    run: (String, String) -> Unit,
) {
    GroupedSection(header = stringResource(R.string.audio_hub_bluetooth), note = stringResource(R.string.audio_hub_bluetooth_note)) {
        ToggleRow(stringResource(R.string.audio_hub_bluetooth), draft.bluetooth ?: state.bluetoothPowered, { on ->
            edit(draft.copy(bluetooth = on))
        }, showDivider = state.bluetoothPowered)
        if (state.bluetoothPowered) {
            ActionRow(stringResource(R.string.audio_hub_pair), onClick = { run("/bluetooth/pairing_mode", "") },
                enabled = !state.bluetoothPairing, showDivider = state.bluetoothPairing)
            if (state.bluetoothPairing) {
                Text(stringResource(R.string.audio_hub_pairing_open), color = Gryonix.colors.secondaryLabel,
                    modifier = Modifier.padding(Metrics.listInset))
            }
        }
    }
}
