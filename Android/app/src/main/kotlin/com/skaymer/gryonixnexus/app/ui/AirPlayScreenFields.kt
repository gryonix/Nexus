package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.PendingChangesBar
import com.skaymer.gryonixnexus.app.ui.design.PendingChangesText
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import com.skaymer.gryonixnexus.catalog.services.PackagedAudioService
import com.skaymer.gryonixnexus.catalog.services.UxPlayService
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** The AirPlay screen's name and the DRM limit */
@Composable
fun ColumnScope.AirPlayScreenFields(
    settings: ServiceSettings,
    showDivider: Boolean,
    edit: ((ServiceSettings) -> ServiceSettings) -> Unit,
) {
    FieldRow(
        label = stringResource(R.string.airplay_screen_name),
        value = settings.uxplayName,
        onValueChange = { name -> edit { it.copy(uxplayName = name) } },
        placeholder = UxPlayService.DEFAULT_NAME,
    )
    InfoRow(stringResource(R.string.airplay_screen_drm), showDivider)
}

/** Changes the installed screen's name */
@Composable
fun AirPlayScreenRows(
    service: ManagedService,
    deployment: Deployment,
    reapply: (Deployment, ManagedService) -> Unit,
) {
    val current = deployment.serviceSettings
    var draft by remember(deployment.id, current) { mutableStateOf(current) }
    Column {
        AirPlayScreenFields(draft, showDivider = false) { change -> draft = change(draft) }
        RowPendingBar(
            visible = draft != current,
            apply = stringResource(R.string.screen_restart),
            note = stringResource(R.string.screen_restart_note),
            onApply = { reapply(deployment.copy(serviceSettings = draft), service) },
            onRevert = { draft = current },
        )
    }
}

/** Changes the name a packaged speaker shows on phones */
@Composable
fun SpeakerNameRows(
    service: ManagedService,
    deployment: Deployment,
    reapply: (Deployment, ManagedService) -> Unit,
) {
    val current = deployment.serviceSettings
    var name by remember(deployment.id, current) { mutableStateOf(current.speakerName) }
    Column {
        FieldRow(
            label = stringResource(R.string.airplay_name),
            value = name,
            onValueChange = { name = it },
            placeholder = deployment.name,
        )
        RowPendingBar(
            visible = name != current.speakerName,
            apply = stringResource(R.string.speaker_restart),
            note = stringResource(R.string.speaker_restart_note),
            onApply = {
                val named = current.copy(speakerName = PackagedAudioService.speakerName(name))
                reapply(deployment.copy(serviceSettings = named), service)
            },
            onRevert = { name = current.speakerName },
        )
    }
}

/** The bar of unapplied edits under a row */
@Composable
private fun RowPendingBar(visible: Boolean, apply: String, note: String, onApply: () -> Unit, onRevert: () -> Unit) {
    Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), contentAlignment = Alignment.Center) {
        PendingChangesBar(
            visible = visible,
            text = PendingChangesText(apply, note, stringResource(R.string.pending_changes_cancel)),
            onApply = onApply,
            onRevert = onRevert,
        )
    }
}
