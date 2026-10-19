package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size
import androidx.compose.ui.text.style.TextAlign
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.CapsuleToggle
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.InfoNoteButton
import com.skaymer.gryonixnexus.app.ui.design.IOSFullSheet
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.ProminentButton
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow as DesignToggleRow
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.agentcontrol.ContainerArchive
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupListing
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupCadence
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupPlan
import com.skaymer.gryonixnexus.agentcontrol.ContainerBackupSchedule
import com.skaymer.gryonixnexus.agentcontrol.ContainerGroup
import com.skaymer.gryonixnexus.agentcontrol.ContainerLogLine
import com.skaymer.gryonixnexus.agentcontrol.ContainerRemovalPreview
import com.skaymer.gryonixnexus.app.containers.ContainersViewModel
import com.skaymer.gryonixnexus.app.containers.GroupOperationKind
import com.skaymer.gryonixnexus.app.containers.GroupOutcome
import com.skaymer.gryonixnexus.app.containers.GroupRun
import com.skaymer.gryonixnexus.app.containers.LOG_LINE_LIMIT
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch

/** One group's log, followed live */
@Composable
fun GroupLogDialog(
    deployment: Deployment,
    group: ContainerGroup,
    containers: ContainersViewModel,
    onClose: () -> Unit,
) {
    var lines by remember { mutableStateOf<List<ContainerLogLine>>(emptyList()) }
    var failure by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(group.key) {
        containers.logs(deployment, group.key)
            .catch { failure = it.message ?: it::class.simpleName }
            .collect { line ->
                val grown = lines + line
                lines = if (grown.size <= LOG_LINE_LIMIT) grown
                else grown.subList(grown.size - LOG_LINE_LIMIT, grown.size)
            }
    }

    IOSFullSheet(
        title = group.displayName,
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_done),
    ) {
        when {
            failure != null -> Column(
                Modifier.padding(horizontal = Metrics.listInset),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    stringResource(R.string.containers_log_failed),
                    style = MaterialTheme.typography.bodyLarge,
                    color = Gryonix.colors.danger,
                )
                Text(
                    failure!!,
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
            lines.isEmpty() -> Row(
                Modifier.padding(horizontal = Metrics.listInset),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CircularProgressIndicator(
                    Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = Gryonix.colors.tertiaryLabel,
                )
                Text(
                    stringResource(R.string.containers_log_waiting),
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
            else -> LogList(lines)
        }
    }
}

@Composable
private fun LogList(lines: List<ContainerLogLine>) {
    val state = androidx.compose.foundation.lazy.rememberLazyListState()
    LaunchedEffect(lines.size) {
        if (lines.isNotEmpty()) state.scrollToItem(lines.size - 1)
    }
    SelectionContainer {
        LazyColumn(Modifier.heightIn(max = 420.dp), state = state) {
            itemsIndexed(lines) { _, line ->
                Column(Modifier.padding(vertical = 2.dp)) {
                    Text(
                        line.container,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        line.text,
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace
                    )
                }
            }
        }
    }
}

@Composable
fun BackupPlanDialog(
    deployment: Deployment,
    group: ContainerGroup,
    containers: ContainersViewModel,
    onClose: () -> Unit,
) {
    var plan by remember { mutableStateOf<ContainerBackupPlan?>(null) }
    var schedule by remember { mutableStateOf<ContainerBackupSchedule?>(null) }
    var paths by remember { mutableStateOf<List<String>>(emptyList()) }
    var volumes by remember { mutableStateOf<List<String>>(emptyList()) }
    var failure by remember { mutableStateOf<String?>(null) }
    var isSaving by remember { mutableStateOf(false) }
    var archives by remember { mutableStateOf<ContainerBackupListing?>(null) }
    var archivesFailure by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    fun adopt(fresh: ContainerBackupPlan) {
        plan = fresh
        paths = fresh.paths
        volumes = fresh.volumes
    }

    LaunchedEffect(group.key) {
        containers.backupPlan(deployment, group.key)
            .onSuccess { adopt(it) }
            .onFailure { failure = it.message ?: it::class.simpleName }
        containers.backupSchedule(deployment, group.key).onSuccess { schedule = it }
        containers.backups(deployment, group.key)
            .onSuccess { archives = it }
            .onFailure { archivesFailure = it.message ?: it::class.simpleName }
    }

    IOSSheet(
        title = stringResource(R.string.containers_backup_plan),
        onClose = { if (!isSaving) onClose() },
        closeLabel = stringResource(R.string.containers_cancel),
        action = SheetAction(
            title = stringResource(R.string.containers_save),
            enabled = plan != null && !isSaving,
            onSelect = {
                val current = plan ?: return@SheetAction
                isSaving = true
                scope.launch {
                    containers.setBackupPlan(
                        deployment, group.key,
                        current.copy(paths = paths, volumes = volumes, isDetected = false),
                    )
                        .onSuccess { onClose() }
                        .onFailure { failure = it.message ?: it::class.simpleName }
                    isSaving = false
                }
            },
        ),
    ) {
            Column(
                Modifier.padding(horizontal = Metrics.listInset),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                failure?.let { Note(it, isError = true) }
                val current = plan
                if (current == null) {
                    if (failure == null) Text(stringResource(R.string.containers_plan_working))
                } else {
                    Header(
                        stringResource(R.string.containers_plan_directories),
                        note = stringResource(R.string.containers_plan_directories_footer),
                    )
                    if (paths.isEmpty()) {
                        Text(stringResource(R.string.containers_plan_no_directories))
                    }
                    paths.forEachIndexed { index, path ->
                        RemovableLine(path) { paths = paths.filterIndexed { i, _ -> i != index } }
                    }

                    if (volumes.isNotEmpty()) {
                        Header(stringResource(R.string.containers_plan_volumes))
                        volumes.forEachIndexed { index, volume ->
                            RemovableLine(volume) {
                                volumes = volumes.filterIndexed { i, _ -> i != index }
                            }
                        }
                    }

                    if (current.databases.isNotEmpty()) {
                        Header(
                            stringResource(R.string.containers_plan_databases),
                            note = stringResource(R.string.containers_plan_databases_footer),
                        )
                        current.databases.forEach { database ->
                            Column {
                                Text("${database.database} · ${database.engine}")
                                Text(
                                    database.container,
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }

                    if (current.stopWhileArchiving) {
                        Text(stringResource(R.string.containers_plan_stops_group))
                        Footnote(stringResource(R.string.containers_plan_stops_group_why))
                    }

                    if (current.notes.isNotEmpty()) {
                        Header(stringResource(R.string.containers_plan_notes))
                        current.notes.forEach { Footnote(it) }
                    }

                    ArchivesSection(archives, archivesFailure)

                    ScheduleRow(schedule) { cadence ->
                        scope.launch {
                            containers.setBackupSchedule(deployment, group.key, cadence)
                                .onSuccess { schedule = it }
                                .onFailure { failure = it.message ?: it::class.simpleName }
                        }
                    }

                    if (!current.isDetected) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            TextButton(onClick = {
                                scope.launch {
                                    containers.setBackupPlan(deployment, group.key, null)
                                        .onSuccess { adopt(it) }
                                        .onFailure { failure = it.message ?: it::class.simpleName }
                                }
                            }) { Text(stringResource(R.string.containers_plan_use_detection)) }
                            InfoNoteButton(
                                title = stringResource(R.string.containers_plan_use_detection),
                                note = stringResource(R.string.containers_plan_use_detection_footer),
                            )
                        }
                    }
                }
            }
    }
}
@Composable
private fun ArchivesSection(listing: ContainerBackupListing?, failure: String?) {
    Header(stringResource(R.string.containers_archives))
    when {
        failure != null -> Note(failure, isError = true)
        listing == null -> Text(stringResource(R.string.containers_archives_reading))
        listing.archives.isEmpty() -> Text(stringResource(R.string.containers_archives_none))
        else -> listing.archives.forEach { archive ->
            Column {
                Text(archive.name, style = MaterialTheme.typography.bodyMedium)
                Text(
                    archiveDetail(archive),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
    listing?.directory?.takeIf { it.isNotEmpty() }?.let {
        Footnote(stringResource(R.string.containers_archives_footer_where, it))
    } ?: Footnote(stringResource(R.string.containers_archives_footer))
}

/** Size and date, or size alone */
@Composable
private fun archiveDetail(archive: ContainerArchive): String {
    val size = android.text.format.Formatter.formatFileSize(
        androidx.compose.ui.platform.LocalContext.current,
        archive.sizeBytes,
    )
    val at = archive.modifiedAt ?: return size
    val formatted = java.text.DateFormat
        .getDateTimeInstance(java.text.DateFormat.MEDIUM, java.text.DateFormat.SHORT)
        .format(java.util.Date(at.toEpochMilli()))
    return "$size · $formatted"
}

@Composable
private fun ScheduleRow(
    schedule: ContainerBackupSchedule?,
    onPick: (ContainerBackupCadence?) -> Unit,
) {
    Header(
        stringResource(R.string.containers_schedule),
        note = stringResource(R.string.containers_schedule_footer),
    )
    Row(
        Modifier.horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        CapsuleToggle(
            text = stringResource(R.string.containers_schedule_off),
            selected = schedule?.cadence == null,
            onClick = { onPick(null) },
        )
        ContainerBackupCadence.entries.forEach { cadence ->
            CapsuleToggle(
                text = stringResource(cadence.label),
                selected = schedule?.cadence == cadence,
                onClick = { onPick(cadence) },
            )
        }
    }
    val outcome = schedule?.lastOutcome.orEmpty()
    if (outcome.isNotEmpty()) {
        Text(
            "${stringResource(R.string.containers_schedule_last_run)}: $outcome",
            style = MaterialTheme.typography.labelSmall,
            color = if (outcome.startsWith("ok")) Gryonix.colors.secondaryLabel
            else Gryonix.colors.danger
        )
    }
}

private val ContainerBackupCadence.label: Int
    get() = when (this) {
        ContainerBackupCadence.DAILY -> R.string.containers_cadence_daily
        ContainerBackupCadence.WEEKLY -> R.string.containers_cadence_weekly
        ContainerBackupCadence.MONTHLY -> R.string.containers_cadence_monthly
    }

@Composable
fun RemovalDialog(
    deployment: Deployment,
    group: ContainerGroup,
    containers: ContainersViewModel,
    onClose: () -> Unit,
    onRemove: (purgeData: Boolean, purgeBackups: Boolean) -> Unit,
) {
    var purgeData by remember { mutableStateOf(false) }
    var purgeBackups by remember { mutableStateOf(false) }
    var preview by remember { mutableStateOf<ContainerRemovalPreview?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(group.key) {
        snapshotFlow { purgeData to purgeBackups }.collect { (data, backups) ->
            containers.removalPreview(deployment, group.key, data, backups)
                .onSuccess { preview = it; failure = null }
                .onFailure { failure = it.message ?: it::class.simpleName }
        }
    }

    IOSSheet(
        title = group.displayName,
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_cancel),
        action = SheetAction(
            title = stringResource(R.string.containers_remove),
            destructive = true,
            onSelect = { onRemove(purgeData, purgeBackups) },
        ),
    ) {
        GroupedSection(footer = stringResource(R.string.containers_remove_footer)) {
            DesignToggleRow(
                title = stringResource(R.string.containers_remove_purge_data),
                checked = purgeData,
                onCheckedChange = { purgeData = it },
            )
            DesignToggleRow(
                title = stringResource(R.string.containers_remove_purge_backups),
                checked = purgeBackups,
                onCheckedChange = { purgeBackups = it },
                showDivider = false,
            )
        }
            Column(
                Modifier.padding(horizontal = Metrics.listInset),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                failure?.let { Note(it, isError = true) }

                preview?.let { plan ->
                    Header(stringResource(R.string.containers_remove_containers))
                    plan.containers.forEach { Mono(it) }
                    if (plan.volumes.isNotEmpty()) {
                        Header(stringResource(R.string.containers_plan_volumes))
                        plan.volumes.forEach { Mono(it) }
                    }
                    if (plan.paths.isNotEmpty()) {
                        Header(stringResource(R.string.containers_plan_directories))
                        plan.paths.forEach { Mono(it) }
                    }
                    if (plan.backupPaths.isNotEmpty()) {
                        Header(stringResource(R.string.containers_remove_backups))
                        plan.backupPaths.forEach { Mono(it) }
                    }
                    if (plan.notes.isNotEmpty()) {
                        Header(
                            stringResource(R.string.containers_remove_left_alone),
                            note = stringResource(R.string.containers_remove_left_alone_footer),
                        )
                        plan.notes.forEach { Footnote(it) }
                    }
                }
            }
    }
}
@Composable
fun GroupRunDialog(containers: ContainersViewModel) {
    val run by containers.run.collectAsState()
    val current = run ?: return
    IOSAlert(
        title = current.key,
        onDismiss = { containers.dismissRun() },
        actions = listOf(
            // Nothing closes this while the host is still being touched.
            AlertAction(
                stringResource(R.string.containers_done),
                preferred = true,
                enabled = current.canBeDismissed,
                onSelect = { containers.dismissRun() },
            ),
        ),
    ) {
        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (current.isRunning) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(
                        Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = Gryonix.colors.tertiaryLabel,
                    )
                    Text(
                        stringResource(current.runningLabel),
                        style = MaterialTheme.typography.bodyMedium,
                        color = Gryonix.colors.secondaryLabel,
                    )
                }
            }
            current.outcome?.let {
                Text(
                    it.sentence(),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.label,
                    textAlign = TextAlign.Center,
                )
            }
            current.failure?.let { Note(it, isError = true) }
            if (current.mayUpdateWithoutBackup) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ProminentButton(
                        stringResource(R.string.containers_update_without_backup),
                        onClick = { containers.updateWithoutBackup() },
                    )
                    InfoNoteButton(
                        title = stringResource(R.string.containers_update_without_backup),
                        note = stringResource(R.string.containers_nothing_to_archive),
                    )
                }
            }
            if (current.lines.isNotEmpty()) {
                SelectionContainer {
                    Column(
                        Modifier.heightIn(max = 240.dp).verticalScroll(rememberScrollState())
                    ) {
                        current.lines.forEach { Mono(it) }
                    }
                }
            }
        }
    }
}
/** What the spinner says */
private val GroupRun.runningLabel: Int
    get() = when (kind) {
        GroupOperationKind.UPDATE ->
            if (skippedBackup) R.string.containers_run_update_no_backup
            else R.string.containers_run_update
        GroupOperationKind.BACKUP -> R.string.containers_run_backup
        GroupOperationKind.REMOVE -> R.string.containers_run_remove
    }

@Composable
private fun GroupOutcome.sentence(): String = when (this) {
    GroupOutcome.Updated -> stringResource(R.string.containers_outcome_updated)
    GroupOutcome.AlreadyCurrent -> stringResource(R.string.containers_outcome_current)
    is GroupOutcome.RolledBack -> stringResource(R.string.containers_outcome_rolled_back, why)
    is GroupOutcome.BackedUp ->
        path?.let { stringResource(R.string.containers_outcome_backed_up, it) }
            ?: stringResource(R.string.containers_outcome_backup_done)
    is GroupOutcome.Removed ->
        if (isGone) stringResource(R.string.containers_outcome_removed)
        else stringResource(R.string.containers_outcome_partly_removed, survivors.joinToString(", "))
}

@Composable
private fun RemovableLine(text: String, onRemove: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(
            text,
            Modifier.weight(1f),
            style = MaterialTheme.typography.bodySmall,
            fontFamily = FontFamily.Monospace,
            color = Gryonix.colors.label,
        )
        IconButton(onClick = onRemove, modifier = Modifier.size(28.dp)) {
            Icon(
                Icons.Filled.Delete,
                contentDescription = stringResource(R.string.containers_remove),
                tint = Gryonix.colors.danger,
                modifier = Modifier.size(18.dp),
            )
        }
    }
}

@Composable
private fun Header(text: String, note: String? = null) {
    if (note == null) {
        Text(
            text.uppercase(),
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.secondaryLabel,
            modifier = Modifier.padding(top = 6.dp),
        )
        return
    }
    Row(
        Modifier.fillMaxWidth().padding(top = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text.uppercase(),
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.secondaryLabel,
            modifier = Modifier.weight(1f),
        )
        InfoNoteButton(title = text, note = note)
    }
}

@Composable
private fun Footnote(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelSmall,
        color = Gryonix.colors.tertiaryLabel,
    )
}
@Composable
private fun Note(text: String, isError: Boolean = false) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = if (isError) Gryonix.colors.danger else Gryonix.colors.label,
        textAlign = TextAlign.Center,
    )
}

@Composable
private fun Mono(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        fontFamily = FontFamily.Monospace,
        color = Gryonix.colors.secondaryLabel,
    )
}
