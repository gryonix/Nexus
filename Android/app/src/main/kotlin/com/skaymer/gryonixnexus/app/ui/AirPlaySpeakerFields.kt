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
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import com.skaymer.gryonixnexus.catalog.services.ShairportSyncService
import com.skaymer.gryonixnexus.servercontrol.Deployment
import gryonixnexusd.v1.AudioOutput

/** The AirPlay speaker's version and name before it is installed */
@Composable
fun ColumnScope.AirPlaySpeakerFields(
    settings: ServiceSettings,
    showDivider: Boolean,
    edit: ((ServiceSettings) -> ServiceSettings) -> Unit,
) {
    AirPlayVersionRow(settings.shairportMode) { mode -> edit { it.copy(shairportMode = mode) } }
    InfoRow(stringResource(R.string.airplay_version_note), true)
    FieldRow(
        label = stringResource(R.string.airplay_name),
        value = settings.shairportName,
        onValueChange = { name -> edit { it.copy(shairportName = name) } },
        placeholder = ShairportSyncService.DEFAULT_NAME,
    )
    InfoRow(stringResource(R.string.airplay_after_install_note), showDivider)
}

/** Which AirPlay generation the speaker speaks */
@Composable
internal fun ColumnScope.AirPlayVersionRow(value: String, infoNote: String? = null, onChoose: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val versions = listOf(
        ShairportSyncService.AIRPLAY_2 to "AirPlay 2",
        ShairportSyncService.AIRPLAY_1 to "AirPlay 1",
    )
    Box {
        ValueRow(
            title = stringResource(R.string.airplay_version),
            value = versions.firstOrNull { it.first == value }?.second ?: versions.first().second,
            onClick = { open = true },
            infoNote = infoNote,
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            for ((mode, label) in versions) {
                DropdownMenuItem(text = { Text(label) }, onClick = { onChoose(mode); open = false })
            }
        }
    }
}

/** Opens the installed speaker's settings */
@Composable
fun AirPlaySpeakerRows(
    service: ManagedService,
    deployment: Deployment,
    reapply: (Deployment, ManagedService) -> Unit,
    audioOutputs: (suspend (Deployment) -> List<AudioOutput>)?,
) {
    var open by remember { mutableStateOf(false) }
    ValueRow(stringResource(R.string.airplay_settings), null, { open = true })
    if (open) {
        AirPlaySpeakerSheet(deployment, audioOutputs, onApply = { reapply(it, service) }) { open = false }
    }
}
