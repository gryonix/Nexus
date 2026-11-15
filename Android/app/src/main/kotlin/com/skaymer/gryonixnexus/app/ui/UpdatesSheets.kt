package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.app.servers.PendingRules
import com.skaymer.gryonixnexus.app.ui.design.ApplyPendingBar
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ListAlt
import androidx.compose.material.icons.outlined.ArrowCircleDown
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.SystemUpdate
import androidx.compose.material3.Icon
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
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
import com.skaymer.gryonixnexus.app.ui.design.StepperRow
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import androidx.compose.ui.text.style.TextAlign
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.agent.AgentSelfUpdateViewModel
import com.skaymer.gryonixnexus.app.servers.BackupPartsModel
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
        leading = { HubIcon(Icons.Outlined.ArrowCircleDown) },
        trailing = {
            Text(
                if (waiting > 0) stringResource(R.string.updates_waiting, waiting) else "",
                style = MaterialTheme.typography.bodyLarge,
                color = if (waiting > 0) Gryonix.colors.accent else Gryonix.colors.secondaryLabel,
            )
            DisclosureChevron()
        },
    ) {
        RowLabel(stringResource(R.string.updates))
    }
}

/** A hub row's icon, in the label colour by default */
@Composable
fun HubIcon(icon: ImageVector, tint: Color = Gryonix.colors.label) {
    Icon(icon, contentDescription = null, modifier = Modifier.size(22.dp), tint = tint)
}

@Composable
fun UpdatesDialog(
    deployment: Deployment,
    updates: UpdatesViewModel,
    onSystemUpdate: (() -> Unit)? = null,
    parts: BackupPartsModel? = null,
    agentSelfUpdate: AgentSelfUpdateViewModel? = null,
    onClose: () -> Unit,
) {
    val state by updates.state.collectAsState()
    LaunchedEffect(deployment.id) {
        updates.load(deployment)
        if (updates.state.value.reports.isEmpty()) updates.check(deployment)
    }
    var page by remember(deployment.id) { mutableStateOf<UpdatesPage?>(null) }
    val drawn = UpdatesViewModel.rows(deployment, state.reports)
    val waiting = drawn.filter { state.reports[it] is ServiceUpdateStatus.Available }

    IOSSheet(title = stringResource(R.string.updates), onClose = onClose, closeLabel = stringResource(R.string.close)) {
        UpdateNumbers(
            waiting = waiting.size,
            current = drawn.count { state.reports[it] is ServiceUpdateStatus.Current },
            checked = state.reports.isNotEmpty(),
            checking = state.checking,
            lastRun = state.runLog.lastRun?.let { formatter.format(it) },
            error = state.errorMessage,
        )
        UpdateActions(
            checking = state.checking,
            waiting = waiting.size,
            onAll = { page = UpdatesPage.SERVICES },
            onCheck = { updates.check(deployment) },
            onUpdateAll = { waiting.forEach { updates.run(deployment, it) } },
        )
        UpdateSettings(
            deployment, state.schedule, parts,
            onOpen = { page = it },
            onSystemUpdate = onSystemUpdate,
            hasAgentPage = agentSelfUpdate != null && deployment.usesAgent,
        )
    }
    when (page) {
        UpdatesPage.SERVICES -> UpdateServicesSheet(deployment, updates) { page = null }
        UpdatesPage.SCHEDULE -> UpdateScheduleSheet(deployment, updates) { page = null }
        UpdatesPage.PARTS -> parts?.let {
            BackupPartsSheet(deployment, it, BackupPartsScope.BEFORE_UPDATE) { page = null }
        }
        UpdatesPage.AGENT -> agentSelfUpdate?.let { AgentUpdatesSheet(deployment, it) { page = null } }
        null -> Unit
    }
}

/** Pages the updates hub opens */
private enum class UpdatesPage { SERVICES, SCHEDULE, PARTS, AGENT }

@Composable
private fun UpdateActions(
    checking: Boolean,
    waiting: Int,
    onAll: () -> Unit,
    onCheck: () -> Unit,
    onUpdateAll: () -> Unit,
) {
    val accent = Gryonix.colors.accent
    GroupedSection {
        ValueRow(
            title = stringResource(R.string.backups_all_services),
            value = null,
            onClick = onAll,
            leading = { HubIcon(Icons.AutoMirrored.Outlined.ListAlt, accent) },
        )
        ActionRow(
            text = stringResource(if (checking) R.string.updates_checking else R.string.updates_check),
            enabled = !checking,
            onClick = onCheck,
            showDivider = waiting > 0,
            leading = {
                if (checking) {
                    CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Gryonix.colors.tertiaryLabel)
                } else {
                    HubIcon(Icons.Outlined.Sync, accent)
                }
            },
        )
        if (waiting > 0) {
            ActionRow(
                text = stringResource(R.string.updates_all, waiting),
                onClick = onUpdateAll,
                showDivider = false,
                leading = { HubIcon(Icons.Outlined.ArrowCircleDown, accent) },
            )
        }
    }
}

@Composable
private fun UpdateSettings(
    deployment: Deployment,
    schedule: AutoUpdateSettings,
    parts: BackupPartsModel?,
    onOpen: (UpdatesPage) -> Unit,
    onSystemUpdate: (() -> Unit)?,
    hasAgentPage: Boolean,
) {
    val accent = Gryonix.colors.accent
    GroupedSection {
        ValueRow(
            title = stringResource(R.string.updates_scheduled),
            value = schedule.schedule.sentence(),
            onClick = { onOpen(UpdatesPage.SCHEDULE) },
            leading = { HubIcon(Icons.Outlined.Schedule, accent) },
        )
        parts?.let { BeforeUpdateRow(deployment, it) { onOpen(UpdatesPage.PARTS) } }
        onSystemUpdate?.let { open ->
            ValueRow(
                title = stringResource(R.string.general_system),
                value = null,
                onClick = open,
                showDivider = hasAgentPage,
                leading = { HubIcon(Icons.Outlined.SystemUpdate, accent) },
            )
        }
        if (hasAgentPage) {
            ValueRow(
                title = stringResource(R.string.agent_auto_update_header),
                value = null,
                onClick = { onOpen(UpdatesPage.AGENT) },
                showDivider = false,
                leading = { HubIcon(Icons.Outlined.Memory, accent) },
            )
        }
    }
}

/** Every service and where its update stands */
@Composable
private fun UpdateServicesSheet(deployment: Deployment, updates: UpdatesViewModel, onClose: () -> Unit) {
    val state by updates.state.collectAsState()
    val drawn = UpdatesViewModel.rows(deployment, state.reports)
    IOSSheet(title = stringResource(R.string.backups_all_services), onClose = onClose, closeLabel = stringResource(R.string.close)) {
        if (drawn.isNotEmpty()) {
            GroupedSection {
                drawn.forEach { id ->
                    StatusRow(
                        name = ServiceRegistry.service(id)?.let(serviceTitles(deployment.id)) ?: id.rawValue,
                        status = state.reports[id],
                        lastRun = state.runLog.records.lastOrNull { it.service == id }?.outcome,
                        onUpdate = { updates.run(deployment, id) },
                        showDivider = id != drawn.last(),
                    )
                }
            }
        }
        LastRun(state.runLog.lastRun?.let { formatter.format(it) })
    }
}

/** The server's update timer, saved on its own page */
@Composable
private fun UpdateScheduleSheet(deployment: Deployment, updates: UpdatesViewModel, onClose: () -> Unit) {
    val state by updates.state.collectAsState()
    val updatable = remember(deployment) { UpdatesViewModel.updatableServices(deployment) }
    var draft by remember(state.schedule) { mutableStateOf(state.schedule) }
    IOSSheet(
        title = stringResource(R.string.updates_scheduled),
        onClose = onClose,
        closeLabel = stringResource(R.string.close),
        bottomBar = {
            ApplyPendingBar(
                visible = PendingRules.waits(
                    draft, state.schedule,
                    valid = !(draft.isOn && draft.services.isEmpty()), busy = state.isSaving,
                ),
                apply = stringResource(R.string.updates_save),
                cancel = stringResource(R.string.pending_changes_cancel),
                onApply = { updates.save(deployment, draft) },
                onRevert = { draft = state.schedule },
            )
        },
    ) {
        ScheduleEditor(
            draft = draft,
            services = serviceTitles(deployment.id).let { title -> updatable.map { it.id to title(it) } },
            onChange = { draft = it },
        )
    }
}

/** The agent's own updates */
@Composable
private fun AgentUpdatesSheet(deployment: Deployment, selfUpdate: AgentSelfUpdateViewModel, onClose: () -> Unit) {
    LaunchedEffect(deployment.id) { selfUpdate.load(deployment) }
    IOSSheet(title = stringResource(R.string.agent_auto_update_header), onClose = onClose, closeLabel = stringResource(R.string.close)) {
        AgentSelfUpdateCard(deployment, selfUpdate)
    }
}

/** Services waiting, services current, the last run */
@Composable
private fun BeforeUpdateRow(deployment: Deployment, parts: BackupPartsModel, onOpen: () -> Unit) {
    val screen by parts.state.collectAsState()
    LaunchedEffect(deployment.id) { parts.load(deployment) }
    ValueRow(
        title = stringResource(R.string.backup_parts_before_update),
        value = backupPartsSummary(screen.parts.choice.beforeUpdate),
        onClick = onOpen,
        leading = { HubIcon(Icons.Outlined.Storage, Gryonix.colors.accent) },
    )
}

@Composable
private fun UpdateNumbers(waiting: Int, current: Int, checked: Boolean, checking: Boolean, lastRun: String?, error: String?) {
    val colors = Gryonix.colors
    GroupedSection(footer = error) {
        when {
            checked -> {
                ValueRow(stringResource(R.string.updates_waiting_title), waiting.toString(), onClick = null,
                    valueColor = if (waiting > 0) colors.warning else colors.secondaryLabel)
                ValueRow(stringResource(R.string.updates_current), current.toString(), onClick = null,
                    showDivider = lastRun != null)
            }
            checking -> ValueRow(stringResource(R.string.updates_checking), null, onClick = null, showDivider = lastRun != null)
            else -> ValueRow(stringResource(R.string.updates_unchecked), null, onClick = null, showDivider = lastRun != null)
        }
        lastRun?.let { ValueRow(stringResource(R.string.updates_last_scheduled_run), it, onClick = null, showDivider = false) }
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
            AiExplainFailure(stringResource(R.string.updates_failed, run.errorMessage.orEmpty()), run.errorMessage, run.log)
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
