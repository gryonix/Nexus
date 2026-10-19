package com.skaymer.gryonixnexus.app.ui

import android.text.format.DateUtils
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.History
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.BackupsViewModel
import com.skaymer.gryonixnexus.app.servers.AllBackupsState
import com.skaymer.gryonixnexus.app.servers.MetricsFormat
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.BackupEntry
import com.skaymer.gryonixnexus.servercontrol.BackupFilter
import com.skaymer.gryonixnexus.servercontrol.BackupOverview
import com.skaymer.gryonixnexus.servercontrol.BackupTotals
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.FleetBackup

private fun sizeText(totals: BackupTotals): String =
    (if (totals.unsized > 0) "≥ " else "") + MetricsFormat.bytes(totals.bytes)

/** Why this server gave no list */
@Composable
private fun ProblemRow(state: AllBackupsState) {
    val failure = state.failure ?: return
    GroupedRow(showDivider = false) {
        Text(failure, style = MaterialTheme.typography.bodySmall, color = Gryonix.colors.danger)
    }
}

/** Backup counts and sizes of this server */
@Composable
fun BackupNumbers(state: AllBackupsState, onOpenAll: () -> Unit) {
    val colors = Gryonix.colors
    val totals = BackupOverview.totals(state.rows)
    GroupedSection {
        if (state.rows.isEmpty()) {
            GroupedRow(showDivider = false) {
                Text(
                    stringResource(if (state.hasLoaded) R.string.backups_none else R.string.backups_loading),
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.secondaryLabel,
                )
            }
        } else {
            ValueRow(stringResource(R.string.backups_total_size), sizeText(totals), onClick = null)
            ValueRow(
                title = stringResource(R.string.backups_count, totals.count),
                value = if (totals.onDrives > 0) {
                    stringResource(R.string.drive_title) + ": " + totals.onDrives
                } else {
                    null
                },
                onClick = null,
            )
            totals.newestMillis?.let {
                ValueRow(stringResource(R.string.backups_last), dateText(it), onClick = null)
            }
        }
        ProblemRow(state)
    }
    GroupedSection {
        ValueRow(
            title = stringResource(R.string.backups_all),
            value = null,
            onClick = onOpenAll,
            showDivider = false,
        )
    }
}

private fun dateText(millis: Long): String =
    DateUtils.formatDateTime(
        null, millis, DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_SHOW_TIME or DateUtils.FORMAT_ABBREV_MONTH,
    )

/** Every backup of this server and its drives, newest first */
@Composable
fun AllBackupsDialog(
    deployment: Deployment,
    backups: BackupsViewModel,
    fleet: List<Deployment> = emptyList(),
    onClose: () -> Unit,
) {
    val all by backups.all.collectAsState()
    var filter by remember { mutableStateOf(BackupFilter()) }
    var choosing by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf(setOf<String>()) }
    var deleting by remember { mutableStateOf(emptyList<FleetBackup>()) }
    var restoring by remember { mutableStateOf<FleetBackup?>(null) }
    val saver = rememberBackupSaver(deployment, backups)

    LaunchedEffect(deployment.id) { backups.loadAll(deployment) }

    val shown = BackupOverview.filtered(all.rows, filter)
    val selectable = shown
    val chosen = all.rows.filter { it.id in selected }

    IOSSheet(
        title = stringResource(R.string.backups_all),
        onClose = onClose,
        closeLabel = stringResource(R.string.close),
        action = SheetAction(
            title = stringResource(if (choosing) R.string.actions_done else R.string.backups_select),
            enabled = choosing || all.rows.isNotEmpty(),
            onSelect = {
                choosing = !choosing
                selected = emptySet()
            },
        ),
    ) {
        BackupFilters(all, filter) { filter = it }
        if (choosing) {
            SelectionSection(
                chosen = chosen.size,
                selectable = selectable.size,
                onSelectAll = {
                    selected = if (chosen.size == selectable.size) emptySet() else selectable.map { it.id }.toSet()
                },
                onSave = { saver.saveMany(chosen.filter { !it.entry.isDirectory && it.entry.drive == null }) },
                onDelete = { deleting = chosen },
            )
        }
        BackupList(
            state = all,
            shown = shown,
            selected = if (choosing) selected else null,
            onToggle = { id -> selected = if (id in selected) selected - id else selected + id },
            onSave = { saver.saveOne(it) },
            onDelete = { deleting = listOf(it) },
            canRestore = { BackupsViewModel.restoreTargets(deployment, it, fleet).isNotEmpty() },
            onRestore = { restoring = it },
        )
    }

    restoring?.let { row ->
        RestoreBackupDialog(deployment, row, fleet, backups) { restoring = null }
    }

    if (deleting.isNotEmpty()) {
        ConfirmAlert(
            title = stringResource(R.string.backups_delete),
            message = deletionMessage(deleting.map { it.entry }),
            confirm = stringResource(R.string.backups_delete),
            cancel = stringResource(R.string.containers_cancel),
            destructive = true,
            onConfirm = {
                backups.deleteMany(deployment, deleting.map { ServiceID(it.serviceId) to it.entry })
                selected = selected - deleting.map { it.id }.toSet()
                deleting = emptyList()
            },
            onCancel = { deleting = emptyList() },
        )
    }
}

@Composable
private fun BackupList(
    state: AllBackupsState,
    shown: List<FleetBackup>,
    /** Null outside choosing mode */
    selected: Set<String>?,
    onToggle: (String) -> Unit,
    onSave: (FleetBackup) -> Unit,
    onDelete: (FleetBackup) -> Unit,
    canRestore: (FleetBackup) -> Boolean,
    onRestore: (FleetBackup) -> Unit,
) {
    GroupedSection {
        ProblemRow(state)
        state.actionError?.let { message ->
            GroupedRow(showDivider = false) {
                Text(message, style = MaterialTheme.typography.bodySmall, color = Gryonix.colors.danger)
            }
        }
        if (shown.isEmpty()) {
            GroupedRow(showDivider = false) {
                Text(
                    stringResource(if (state.isLoading) R.string.backups_loading else R.string.backups_none),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
        }
        shown.forEach { row ->
            if (selected != null) {
                CheckRow(
                    title = row.entry.displayName,
                    subtitle = rowDetail(row),
                    checked = row.id in selected,
                    onClick = { onToggle(row.id) },
                    showDivider = row != shown.last(),
                )
            } else {
                BackupRow(
                    row = row,
                    canSave = row.entry.drive == null,
                    canRestore = canRestore(row),
                    showDivider = row != shown.last(),
                    onSave = { onSave(row) },
                    onDelete = { onDelete(row) },
                    onRestore = { onRestore(row) },
                )
            }
        }
    }
}

/** What can be done with the ticked backups */
@Composable
private fun SelectionSection(
    chosen: Int,
    selectable: Int,
    onSelectAll: () -> Unit,
    onSave: () -> Unit,
    onDelete: () -> Unit,
) {
    GroupedSection {
        ValueRow(
            title = stringResource(R.string.backups_selected_count, chosen),
            value = stringResource(if (chosen == selectable) R.string.backups_deselect_all else R.string.security_select_all),
            onClick = onSelectAll,
        )
        ActionRow(
            text = stringResource(R.string.backups_save_to_device) + " ($chosen)",
            onClick = onSave,
            enabled = chosen > 0,
        )
        ActionRow(
            text = stringResource(R.string.backups_delete) + " ($chosen)",
            onClick = onDelete,
            enabled = chosen > 0,
            danger = true,
            showDivider = false,
        )
    }
}

/** What a delete confirmation says, naming the drive when needed */
@Composable
internal fun deletionMessage(entries: List<BackupEntry>): String {
    val single = entries.singleOrNull()
    val drive = single?.drive
    return when {
        single != null && drive != null -> stringResource(R.string.backups_delete_confirm_drive, single.displayName, drive)
        single != null -> stringResource(R.string.backups_delete_confirm, single.displayName)
        entries.any { it.drive != null } -> stringResource(R.string.backups_delete_many_drives, entries.size)
        else -> stringResource(R.string.backups_delete_many, entries.size)
    }
}

@Composable
private fun rowDetail(row: FleetBackup): String = listOfNotNull(
    row.serviceName,
    stringResource(
        R.string.backups_entry_detail,
        row.entry.sizeText,
        row.entry.modifiedAtMillis?.let(::dateText) ?: row.entry.dateText,
    ),
    row.entry.drive?.let { stringResource(R.string.drive_copy_on, it) },
).joinToString(" · ")

@Composable
private fun BackupFilters(
    state: AllBackupsState,
    filter: BackupFilter,
    onChange: (BackupFilter) -> Unit,
) {
    val allServices = stringResource(R.string.backups_all_services)
    val services = state.rows.map { it.serviceId to it.serviceName }.distinct()
    GroupedSection {
        ChoiceRow(
            title = stringResource(R.string.services),
            value = services.firstOrNull { it.first == filter.serviceId }?.second ?: allServices,
            options = listOf(allServices to { onChange(filter.copy(serviceId = null)) }) +
                services.map { it.second to { onChange(filter.copy(serviceId = it.first)) } },
        )
        GroupedRow(showDivider = false) {
            PlacePicker(filter.place) { onChange(filter.copy(place = it)) }
        }
    }
}

/** All, on the server, or on drives */
@Composable
internal fun PlacePicker(place: BackupFilter.Place, onChange: (BackupFilter.Place) -> Unit) {
    IOSSegmentedControl(
        segments = BackupFilter.Place.entries,
        selected = place,
        label = {
            stringResource(
                when (it) {
                    BackupFilter.Place.ANY -> R.string.backups_place_all
                    BackupFilter.Place.SERVER -> R.string.backups_on_servers
                    BackupFilter.Place.DRIVES -> R.string.backups_on_drives
                },
            )
        },
        onSelect = onChange,
        modifier = Modifier.padding(vertical = 4.dp),
    )
}

@Composable
private fun BackupRow(
    row: FleetBackup,
    canSave: Boolean,
    canRestore: Boolean,
    showDivider: Boolean,
    onSave: () -> Unit,
    onDelete: () -> Unit,
    onRestore: () -> Unit,
) {
    val colors = Gryonix.colors
    GroupedRow(
        showDivider = showDivider,
        trailing = {
            if (canRestore) {
                IconButton(onClick = onRestore, modifier = Modifier.size(28.dp)) {
                    Icon(
                        Icons.Filled.History,
                        contentDescription = stringResource(R.string.backups_restore),
                        tint = colors.accent,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
            if (canSave) PlainButton(text = stringResource(R.string.backups_save_to_device), onClick = onSave)
            IconButton(onClick = onDelete, modifier = Modifier.size(28.dp)) {
                Icon(
                    Icons.Filled.Delete,
                    contentDescription = stringResource(R.string.backups_delete),
                    tint = colors.danger,
                    modifier = Modifier.size(18.dp),
                )
            }
        },
    ) {
        RowLabel(row.entry.displayName, rowDetail(row))
    }
}
