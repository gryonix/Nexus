package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import gryonixnexusd.v1.AudioOutput

@Composable
fun ColumnScope.OutputRows(
    outputs: List<AudioOutput>?,
    failed: String?,
    output: String,
    mixer: String,
    onOutput: (String) -> Unit,
    onMixer: (String) -> Unit,
) {
    val title = stringResource(R.string.speaker_output)
    if (outputs.isNullOrEmpty()) {
        val shown = if (failed == null) stringResource(R.string.speaker_reading) else output
        ValueRow(title, shown, null, subtitle = failed, showDivider = false, infoNote = stringResource(R.string.speaker_info_output))
        return
    }
    val systemDefault = stringResource(R.string.speaker_system_default)
    val choices = (if (outputs.any { it.device == output }) outputs else outputs + AudioOutput(device = output))
        .map { it.device to (if (it.device == "default") systemDefault else it.title.ifEmpty { it.device }) }
    MenuRow(title, choices, output, true, stringResource(R.string.speaker_info_output), onOutput)
    val own = outputs.firstOrNull { it.device == output }?.mixers.orEmpty()
    val mixers = if (mixer.isEmpty() || mixer in own) own else own + mixer
    MenuRow(stringResource(R.string.speaker_volume_control),
        listOf("" to stringResource(R.string.speaker_software)) + mixers.map { it to it }, mixer, false, stringResource(R.string.speaker_info_mixer), onMixer)
}

@Composable
private fun ColumnScope.MenuRow(
    title: String,
    choices: List<Pair<String, String>>,
    value: String,
    divider: Boolean,
    infoNote: String,
    onChoose: (String) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        ValueRow(title, choices.firstOrNull { it.first == value }?.second ?: value, { open = true }, showDivider = divider,
            infoNote = infoNote)
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            for ((key, label) in choices) {
                DropdownMenuItem(text = { Text(label) }, onClick = { onChoose(key); open = false })
            }
        }
    }
}
