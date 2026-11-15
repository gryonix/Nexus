package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.PendingChangesBar
import com.skaymer.gryonixnexus.app.ui.design.PendingChangesText
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.app.ui.design.WheelRow
import com.skaymer.gryonixnexus.catalog.services.ShairportSyncOptions
import com.skaymer.gryonixnexus.catalog.services.ShairportSyncService
import com.skaymer.gryonixnexus.servercontrol.Deployment
import gryonixnexusd.v1.AudioOutput

/** Everything the AirPlay speaker can be set to */
@Composable
fun AirPlaySpeakerSheet(
    deployment: Deployment,
    audioOutputs: (suspend (Deployment) -> List<AudioOutput>)?,
    onApply: (Deployment) -> Unit,
    onClose: () -> Unit,
) {
    val current = deployment.serviceSettings
    var draft by remember(deployment.id) { mutableStateOf(current) }
    var values by remember(deployment.id) {
        mutableStateOf(ShairportSyncOptions.parsed(current.shairportOptions).toMap())
    }
    var outputs by remember { mutableStateOf<List<AudioOutput>?>(null) }
    var failed by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(deployment.id) {
        runCatching { audioOutputs?.invoke(deployment).orEmpty() }
            .onSuccess { outputs = it }.onFailure { failed = it.message ?: it.toString() }
    }
    val result = draft.copy(shairportOptions = ShairportSyncOptions.text(values))
    IOSSheet(
        title = stringResource(R.string.airplay_settings),
        onClose = onClose,
        closeLabel = stringResource(R.string.close),
        bottomBar = {
            PendingChangesBar(
                visible = result != current,
                text = PendingChangesText(
                    apply = stringResource(R.string.speaker_restart),
                    note = stringResource(R.string.speaker_restart_note),
                    cancel = stringResource(R.string.pending_changes_cancel),
                ),
                onApply = { onApply(deployment.copy(serviceSettings = result)); onClose() },
                onRevert = {
                    draft = current
                    values = ShairportSyncOptions.parsed(current.shairportOptions).toMap()
                },
            )
        },
    ) {
        GroupedSection(header = stringResource(R.string.speaker_section_speaker), note = stringResource(R.string.airplay_version_note)) {
            AirPlayVersionRow(draft.shairportMode, stringResource(R.string.airplay_version_note)) { mode -> draft = draft.copy(shairportMode = mode) }
            FieldRow(
                label = stringResource(R.string.airplay_name), value = draft.shairportName,
                onValueChange = { draft = draft.copy(shairportName = it) },
                placeholder = ShairportSyncService.DEFAULT_NAME, showDivider = false,
                infoNote = stringResource(R.string.speaker_info_name),
            )
        }
        GroupedSection(header = stringResource(R.string.speaker_section_output), note = stringResource(R.string.speaker_output_note)) {
            OutputRows(outputs, failed, ShairportSyncService.playable(draft.shairportOutput), values["mixer_control_name"].orEmpty(),
                onOutput = { draft = draft.copy(shairportOutput = it) },
                onMixer = { values = values + ("mixer_control_name" to it) })
        }
        if (ShairportSyncService.playable(draft.shairportOutput).contains("vc4hdmi")) {
            val shown = SpeakerSettingsCatalog.hdmiVolume.take(if (values["cec_volume"] == "yes") 8 else 1)
            SettingsSection(R.string.speaker_section_hdmi, R.string.speaker_hdmi_note, shown, values) { values = it }
        }
        SettingsSection(R.string.speaker_section_volume, R.string.speaker_volume_note, SpeakerSettingsCatalog.sound, values) { values = it }
        SettingsSection(R.string.speaker_section_timing, R.string.speaker_timing_note, SpeakerSettingsCatalog.timing, values) { values = it }
        SettingsSection(R.string.speaker_section_format, R.string.speaker_format_note, SpeakerSettingsCatalog.format, values) { values = it }
        SettingsSection(R.string.speaker_section_sessions, R.string.speaker_sessions_note, SpeakerSettingsCatalog.sessions, values) { values = it }
        GroupedSection {
            ActionRow(text = stringResource(R.string.speaker_reset), onClick = { values = emptyMap() },
                enabled = values.isNotEmpty(), showDivider = false)
        }
    }
}

@Composable
private fun SettingsSection(
    header: Int,
    note: Int,
    settings: List<SpeakerSetting>,
    values: Map<String, String>,
    onChange: (Map<String, String>) -> Unit,
) {
    GroupedSection(header = stringResource(header), note = stringResource(note)) {
        settings.forEachIndexed { index, setting ->
            SettingRow(setting, values, index < settings.lastIndex, onChange)
        }
    }
}

@Composable
internal fun ColumnScope.SettingRow(
    setting: SpeakerSetting,
    values: Map<String, String>,
    divider: Boolean,
    onChange: (Map<String, String>) -> Unit,
) {
    val title = stringResource(setting.title)
    when (val control = setting.control) {
        is SpeakerSetting.Control.Toggle -> ToggleRow(title, values[setting.key] == "yes",
            { onChange(values + (setting.key to if (it) "yes" else "")) }, showDivider = divider,
            infoNote = stringResource(setting.info))
        is SpeakerSetting.Control.Choice -> ChoiceRow(title, control.choices, values[setting.key].orEmpty(), divider,
            stringResource(setting.info)) {
            onChange(values + (setting.key to it))
        }
        is SpeakerSetting.Control.Number -> NumberRow(setting, control.standard, setting.range.start, control.step,
            control.unit, stringResource(R.string.speaker_default), values, divider, onChange)
        is SpeakerSetting.Control.Buffer -> NumberRow(setting, control.standard, control.minimal, control.step,
            control.unit, stringResource(R.string.speaker_choice_auto), values, divider, onChange)
    }
}

/** A number picked on a wheel */
@Composable
private fun ColumnScope.NumberRow(
    setting: SpeakerSetting,
    standard: Double,
    low: Double,
    step: Double,
    unit: String,
    unset: String,
    values: Map<String, String>,
    divider: Boolean,
    onChange: (Map<String, String>) -> Unit,
) {
    val standardText = SpeakerSettingsCatalog.plain(standard)
    val stored = values[setting.key].orEmpty()
    val numbers = SpeakerSettingsCatalog.wheelValues(low, setting.range.endInclusive, step, standardText, stored)
    val chosen = if (stored == standardText) "" else stored
    WheelRow(
        title = stringResource(setting.title),
        choices = numbers.map { if (it.isEmpty()) "$unset · $standardText $unit" else "$it $unit" },
        selected = numbers.indexOf(chosen),
        onSelect = { index -> onChange(values + (setting.key to numbers[index])) },
        showDivider = divider,
        infoNote = stringResource(setting.info),
    )
}

@Composable
private fun ColumnScope.ChoiceRow(
    title: String,
    choices: List<Pair<String, Int>>,
    value: String,
    divider: Boolean,
    infoNote: String,
    onChoose: (String) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    val defaultLabel = stringResource(R.string.speaker_default)
    val labels = choices.map { it.first to stringResource(it.second) }
    Box {
        ValueRow(title, labels.firstOrNull { it.first == value }?.second ?: defaultLabel, { open = true }, showDivider = divider,
            infoNote = infoNote)
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(text = { Text(defaultLabel) }, onClick = { onChoose(""); open = false })
            for ((key, label) in labels) {
                DropdownMenuItem(text = { Text(label) }, onClick = { onChoose(key); open = false })
            }
        }
    }
}
