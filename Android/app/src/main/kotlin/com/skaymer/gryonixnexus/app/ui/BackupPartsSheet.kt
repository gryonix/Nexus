package com.skaymer.gryonixnexus.app.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.BackupPartsModel
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.catalog.BackupPart
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.BackupPartScope
import com.skaymer.gryonixnexus.servercontrol.BackupPartsChange
import com.skaymer.gryonixnexus.servercontrol.BackupPartsState
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.get

/** Which kind of backup the sheet edits */
typealias BackupPartsScope = BackupPartScope

@Composable
fun BackupPartsSheet(deployment: Deployment, model: BackupPartsModel, scope: BackupPartsScope, onClose: () -> Unit) {
    val screen by model.state.collectAsState()
    LaunchedEffect(deployment.id) { model.load(deployment) }
    val title = stringResource(
        if (scope == BackupPartsScope.REGULAR) R.string.backup_parts_title else R.string.backup_parts_before_update,
    )
    IOSSheet(title = title, onClose = onClose, closeLabel = stringResource(R.string.close)) {
        if (screen.loaded && !screen.parts.supported) {
            PartsNote(stringResource(R.string.backup_parts_outdated), warning = false)
        } else {
            val listed = screen.listed.sortedBy(::serviceName)
            SharedPartsSection(screen.parts, scope, listed) { model.save(deployment, it) }
            listed.forEach { service ->
                ServicePartsSection(screen.parts, scope, service) { model.save(deployment, it) }
            }
        }
        screen.error?.let { PartsNote(it, warning = true) }
    }
}

@Composable
private fun SharedPartsSection(
    parts: BackupPartsState,
    scope: BackupPartsScope,
    listed: List<String>,
    onChange: (BackupPartsChange) -> Unit,
) {
    val footer = stringResource(
        if (scope == BackupPartsScope.REGULAR) R.string.backup_parts_regular_footer else R.string.backup_parts_update_footer,
    )
    val every = if (listed.isEmpty()) "" else "\n" + stringResource(R.string.backup_parts_shared_footer)
    GroupedSection(header = stringResource(R.string.backup_parts_every_service), footer = footer + every) {
        BackupPart.entries.forEach { part ->
            ToggleRow(
                title = backupPartName(part),
                subtitle = stringResource(partNote(part)),
                checked = parts.sharedIsOn(part, scope, listed),
                onCheckedChange = { on -> onChange(parts.settingShared(part, scope, on, listed)) },
                showDivider = part != BackupPart.entries.last(),
            )
        }
    }
}

@Composable
private fun ServicePartsSection(
    parts: BackupPartsState,
    scope: BackupPartsScope,
    service: String,
    onChange: (BackupPartsChange) -> Unit,
) {
    GroupedSection(header = serviceName(service)) {
        BackupPart.entries.forEach { part ->
            ToggleRow(
                title = backupPartName(part),
                checked = part in parts.choiceFor(service)[scope],
                onCheckedChange = { on -> onChange(parts.settingService(service, part, scope, on)) },
                showDivider = part != BackupPart.entries.last(),
            )
        }
    }
}

/** A service's name, or its id when unknown */
private fun serviceName(id: String): String = ServiceRegistry.service(ServiceID(id))?.displayName ?: id

@Composable
private fun PartsNote(text: String, warning: Boolean) {
    GroupedSection {
        GroupedRow(showDivider = false) {
            Text(
                text,
                style = MaterialTheme.typography.bodyMedium,
                color = if (warning) Gryonix.colors.warning else Gryonix.colors.secondaryLabel,
            )
        }
    }
}

@Composable
fun backupPartName(part: BackupPart): String = stringResource(
    when (part) {
        BackupPart.FILES -> R.string.backup_part_files
        BackupPart.SETTINGS -> R.string.backup_part_settings
        BackupPart.DATABASES -> R.string.backup_part_databases
    },
)

private fun partNote(part: BackupPart): Int = when (part) {
    BackupPart.FILES -> R.string.backup_part_files_note
    BackupPart.SETTINGS -> R.string.backup_part_settings_note
    BackupPart.DATABASES -> R.string.backup_part_databases_note
}

/** The chosen parts in one line */
@Composable
fun backupPartsSummary(parts: Set<BackupPart>): String {
    val names = BackupPart.entries.filter { it in parts }.map { backupPartName(it) }
    return if (names.isEmpty()) stringResource(R.string.backup_parts_nothing) else names.joinToString(", ")
}
