package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.app.ui.design.RunLog
import com.skaymer.gryonixnexus.app.ui.design.RunProgressRow
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.StepperRow
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import androidx.compose.ui.text.style.TextAlign
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.servers.UpdatesViewModel
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.ServiceUpdateStatus
import com.skaymer.gryonixnexus.servercontrol.AutoUpdateSettings
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateRunRecord
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** The row on the server screen that leads to updates */
@Composable
fun UpdatesCard(
    deployment: Deployment,
    updates: UpdatesViewModel,
    onOpen: () -> Unit,
    showDivider: Boolean = true,
) {
    val state by updates.state.collectAsState()
    val waiting = UpdatesViewModel.rows(deployment, state.reports)
        .count { state.reports[it] is ServiceUpdateStatus.Available }
    GroupedRow(
        showDivider = showDivider,
        onClick = onOpen,
        trailing = {
            Text(
                if (waiting > 0) stringResource(R.string.updates_waiting, waiting)
                else if (state.hasLoadedSchedule) state.schedule.schedule.sentence()
                else "",
                style = MaterialTheme.typography.bodyLarge,
                color = if (waiting > 0) Gryonix.colors.accent else Gryonix.colors.secondaryLabel,
            )
            DisclosureChevron()
        },
    ) {
        RowLabel(stringResource(R.string.updates))
    }
}

@Composable
fun UpdatesDialog(
    deployment: Deployment,
    updates: UpdatesViewModel,
    onClose: () -> Unit,
) {
    val state by updates.state.collectAsState()
    LaunchedEffect(deployment.id) { updates.load(deployment) }

    val updatable = remember(deployment) { UpdatesViewModel.updatableServices(deployment) }
    val drawn = UpdatesViewModel.rows(deployment, state.reports)
    var draft by remember(state.schedule) { mutableStateOf(state.schedule) }

    IOSSheet(
        title = stringResource(R.string.updates),
        onClose = onClose,
        closeLabel = stringResource(R.string.close),
        action = SheetAction(
            title = stringResource(R.string.updates_save),
            enabled = !state.isSaving && !(draft.isOn && draft.services.isEmpty()),
            onSelect = { updates.save(deployment, draft) },
        ),
    ) {
        GroupedSection(footer = state.errorMessage) {
            ActionRow(
                text = stringResource(
                    if (state.checking) R.string.updates_checking else R.string.updates_check
                ),
                enabled = !state.checking,
                onClick = { updates.check(deployment) },
                showDivider = false,
                leading = if (!state.checking) {
                    null
                } else {
                    {
                        CircularProgressIndicator(
                            Modifier.size(16.dp),
                            strokeWidth = 2.dp,
                            color = Gryonix.colors.tertiaryLabel,
                        )
                    }
                },
            )
        }

        if (drawn.isNotEmpty()) {
            GroupedSection {
                drawn.forEach { id ->
                    StatusRow(
                        name = ServiceRegistry.service(id)?.displayName ?: id.rawValue,
                        status = state.reports[id],
                        lastRun = state.runLog.records.lastOrNull { it.service == id }?.outcome,
                        onUpdate = { updates.run(deployment, id) },
                        showDivider = id != drawn.last(),
                    )
                }
            }
        }

        LastRun(state.runLog.lastRun?.let { formatter.format(it) })

        ScheduleEditor(
            draft = draft,
            services = updatable.map { it.id to it.displayName },
            onChange = { draft = it },
        )
    }
}

@Composable
private fun StatusRow(
    name: String,
    status: ServiceUpdateStatus?,
    onUpdate: () -> Unit,
    showDivider: Boolean = true,
    lastRun: ServiceUpdateRunRecord.Outcome? = null,
) {
    val colors = Gryonix.colors
    GroupedRow(
        showDivider = showDivider,
        trailing = {
            when (status) {
                is ServiceUpdateStatus.Available -> Column(horizontalAlignment = Alignment.End) {
                    Text(
                        stringResource(R.string.updates_available),
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.warning,
                    )
                    Text(
                        status.images.joinToString(", "),
                        style = MaterialTheme.typography.labelSmall,
                        color = colors.tertiaryLabel,
                    )
                    PlainButton(stringResource(R.string.updates_now), onUpdate)
                }
                ServiceUpdateStatus.Current -> Muted(stringResource(R.string.updates_current))
                ServiceUpdateStatus.SelfManaged -> Muted(stringResource(R.string.updates_self))
                ServiceUpdateStatus.RebuiltBySetup -> Muted(stringResource(R.string.updates_setup))
                ServiceUpdateStatus.Unknown -> Text(
                    stringResource(R.string.updates_unknown),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.warning,
                )
                null -> Muted(stringResource(R.string.updates_unchecked))
            }
        },
    ) {
        Column(Modifier.weight(1f)) {
            Text(name, style = MaterialTheme.typography.bodyLarge, color = colors.label)
            lastRun?.let { LastRunCaption(it) }
        }
    }
}

/** How the last update of a service ended */
@Composable
private fun LastRunCaption(outcome: ServiceUpdateRunRecord.Outcome) {
    val colors = Gryonix.colors
    val (text, color) = when (outcome) {
        ServiceUpdateRunRecord.Outcome.Updated ->
            stringResource(R.string.updates_last_done) to colors.tertiaryLabel
        is ServiceUpdateRunRecord.Outcome.RolledBack ->
            stringResource(R.string.updates_last_rolled_back, outcome.reason) to colors.warning
        is ServiceUpdateRunRecord.Outcome.Failed ->
            stringResource(R.string.updates_last_failed, outcome.reason) to colors.danger
    }
    Text(text, style = MaterialTheme.typography.labelSmall, color = color, maxLines = 2)
}

/** When the timer last ran */
@Composable
private fun LastRun(at: String?) {
    if (at == null) return
    Text(
        stringResource(R.string.updates_last_run, at),
        style = MaterialTheme.typography.labelSmall,
        color = Gryonix.colors.secondaryLabel,
    )
}

/** The schedule the SERVER keeps */
@Composable
private fun ScheduleEditor(
    draft: AutoUpdateSettings,
    services: List<Pair<ServiceID, String>>,
    onChange: (AutoUpdateSettings) -> Unit,
) {
    val schedule = draft.schedule

    GroupedSection(
        footer = if (draft.isOn) stringResource(R.string.updates_warning) else null,
    ) {
        ToggleRow(
            title = stringResource(R.string.updates_automatically),
            checked = draft.isOn,
            onCheckedChange = { on ->
                onChange(
                    draft.copy(
                        schedule = if (on) CommandCatalog.Backups.Schedule.Days(1, 4, 0)
                        else CommandCatalog.Backups.Schedule.Off
                    )
                )
            },
            showDivider = draft.isOn,
        )
        if (draft.isOn) {
            ScheduleFieldRows(schedule, defaultHour = 4) { onChange(draft.copy(schedule = it)) }
            services.forEachIndexed { index, (id, name) ->
                ToggleRow(
                    title = name,
                    checked = id.rawValue in draft.services,
                    onCheckedChange = { on ->
                        onChange(
                            draft.copy(
                                services = if (on) draft.services + id.rawValue
                                else draft.services - id.rawValue
                            )
                        )
                    },
                    showDivider = index != services.lastIndex,
                )
            }
        }
    }
}

@Composable
fun UpdateRunDialog(updates: UpdatesViewModel) {
    val state by updates.state.collectAsState()
    val run = state.run ?: return
    val name = ServiceRegistry.service(run.service)?.displayName ?: run.service.rawValue
    IOSAlert(
        title = stringResource(R.string.updates_updating, name),
        onDismiss = { if (run.isFinished) updates.clearRun() },
        actions = listOf(
            // Nothing closes this while the host is still being touched.
            AlertAction(
                stringResource(R.string.containers_done),
                preferred = true,
                enabled = run.isFinished,
                onSelect = { updates.clearRun() },
            ),
        ),
    ) {
        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (!run.isFinished) RunProgressRow(stringResource(R.string.updates_running))
            when (val outcome = run.outcome) {
                ServiceUpdateRunRecord.Outcome.Updated -> Text(
                    stringResource(R.string.updates_finished),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.label,
                    textAlign = TextAlign.Center,
                )
                is ServiceUpdateRunRecord.Outcome.RolledBack -> Text(
                    stringResource(R.string.updates_rolled_back, outcome.reason),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.warning,
                    textAlign = TextAlign.Center,
                )
                is ServiceUpdateRunRecord.Outcome.Failed -> Text(
                    stringResource(R.string.updates_failed, outcome.reason),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.danger,
                    textAlign = TextAlign.Center,
                )
                null -> Unit
            }
            run.errorMessage?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.danger,
                    textAlign = TextAlign.Center,
                )
            }
            if (run.continuesOnServer) {
                Text(
                    stringResource(R.string.updates_continues_on_server),
                    style = MaterialTheme.typography.bodySmall,
                    textAlign = TextAlign.Center,
                )
            }
            RunLog(run.log)
        }
    }
}

@Composable
private fun Muted(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant
    )
}

@Composable
private fun CommandCatalog.Backups.Schedule.sentence(): String = when (this) {
    CommandCatalog.Backups.Schedule.Off -> stringResource(R.string.updates_off)
    is CommandCatalog.Backups.Schedule.Hours ->
        stringResource(R.string.updates_summary_hours, count, minute)
    is CommandCatalog.Backups.Schedule.Days ->
        stringResource(R.string.updates_summary_days, count, hour, minute)
}

private val formatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("d MMM yyyy HH:mm").withZone(ZoneId.systemDefault())
