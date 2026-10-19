package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.agentcontrol.ContainerAction
import com.skaymer.gryonixnexus.agentcontrol.ContainerDetail
import com.skaymer.gryonixnexus.agentcontrol.ContainerGroup
import com.skaymer.gryonixnexus.agentcontrol.ContainerGroupStatus
import com.skaymer.gryonixnexus.app.containers.ContainersViewModel
import com.skaymer.gryonixnexus.app.containers.GroupOperationKind
import com.skaymer.gryonixnexus.app.containers.ServerContainers
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.launch

/** "Containers" — every machine in the fleet and everything it runs */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ContainersSection(
    fleet: FleetRepository,
    containers: ContainersViewModel,
    only: String? = null,
) {
    val allDeployments by fleet.deployments.collectAsState()
    val deployments = remember(allDeployments, only) {
        if (only == null) allDeployments else allDeployments.filter { it.id == only }
    }
    val states by containers.states.collectAsState()
    val busy by containers.busy.collectAsState()
    var showing by remember { mutableStateOf<ContainerDetail?>(null) }
    var sheet by remember { mutableStateOf<GroupSheet?>(null) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(deployments.map { it.id }) { containers.load(deployments) }
    DisposableEffect(Unit) { onDispose { containers.stop() } }

    if (deployments.isEmpty()) {
        EmptySection(R.string.containers_none, R.string.containers_none_hint)
        return
    }

    val isRefreshing by containers.isRefreshing.collectAsState()
    PullToRefreshBox(
        isRefreshing = isRefreshing,
        onRefresh = { containers.load(deployments) },
        modifier = Modifier.fillMaxSize()
    ) {
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        deployments.forEach { server ->
            item(key = "head-${server.id}") {
                Row(
                    Modifier.fillMaxWidth().padding(
                        start = Metrics.listInset + 4.dp,
                        end = Metrics.listInset + 4.dp,
                        bottom = 2.dp,
                    ),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        server.name.uppercase(),
                        style = MaterialTheme.typography.bodySmall,
                        color = Gryonix.colors.secondaryLabel,
                    )
                    Text(
                        containers.summary(server.id),
                        style = MaterialTheme.typography.bodySmall,
                        color = Gryonix.colors.tertiaryLabel,
                    )
                }
            }
            when (val state = states[server.id]) {
                null, ServerContainers.Loading -> item(key = "load-${server.id}") { Loading() }
                ServerContainers.NeedsAgent -> item(key = "agent-${server.id}") {
                    Note(stringResource(R.string.containers_needs_agent))
                }
                is ServerContainers.Failed -> item(key = "fail-${server.id}") {
                    Note(state.message, isError = true)
                }
                is ServerContainers.Loaded -> {
                    val reason = state.inventory.unavailableReason
                    if (reason != null) {
                        item(key = "engine-${server.id}") {
                            Note(
                                "${stringResource(R.string.containers_engine_down_title)}: $reason",
                                isError = true
                            )
                        }
                    } else if (state.inventory.groups.isEmpty()) {
                        item(key = "none-${server.id}") {
                            Note(stringResource(R.string.containers_empty_host))
                        }
                    } else {
                        items(state.inventory.groups, key = { "${server.id}-${it.key}" }) { group ->
                            GroupCard(
                                group = group,
                                isBusy = group.key in busy,
                                onAction = { containers.control(server, group.key, it) },
                                onInspect = { name ->
                                    scope.launch { showing = containers.detail(server, name) }
                                },
                                onLongVerb = { kind ->
                                    when (kind) {
                                        GroupSheetKind.UPDATE ->
                                            containers.start(server, group.key, GroupOperationKind.UPDATE)
                                        GroupSheetKind.BACKUP_NOW ->
                                            containers.start(server, group.key, GroupOperationKind.BACKUP)
                                        else -> sheet = GroupSheet(server, group, kind)
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }
    }

    showing?.let { detail -> DetailDialog(detail) { showing = null } }

    when (val open = sheet) {
        null -> Unit
        else -> when (open.kind) {
            GroupSheetKind.LOG ->
                GroupLogDialog(open.server, open.group, containers) { sheet = null }
            GroupSheetKind.PLAN ->
                BackupPlanDialog(open.server, open.group, containers) { sheet = null }
            GroupSheetKind.REMOVE -> RemovalDialog(
                deployment = open.server,
                group = open.group,
                containers = containers,
                onClose = { sheet = null },
                onRemove = { purgeData, purgeBackups ->
                    sheet = null
                    containers.start(
                        open.server, open.group.key, GroupOperationKind.REMOVE,
                        purgeData = purgeData, purgeBackups = purgeBackups,
                    )
                }
            )
            else -> Unit
        }
    }

    GroupRunDialog(containers)
}

/** Which of a group's own screens is open */
private enum class GroupSheetKind { LOG, PLAN, BACKUP_NOW, UPDATE, REMOVE }

private data class GroupSheet(
    val server: Deployment,
    val group: ContainerGroup,
    val kind: GroupSheetKind,
)

@Composable
private fun GroupCard(
    group: ContainerGroup,
    isBusy: Boolean,
    onAction: (ContainerAction) -> Unit,
    onInspect: (String) -> Unit,
    onLongVerb: (GroupSheetKind) -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    GroupedSection {
        GroupedRow(
            showDivider = group.containers.isNotEmpty(),
            trailing = {
                if (isBusy) {
                    CircularProgressIndicator(
                        Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = Gryonix.colors.tertiaryLabel,
                    )
                } else {
                    Box {
                        IconButton(
                            onClick = { menuOpen = true },
                            modifier = Modifier.size(30.dp),
                        ) {
                            Icon(
                                Icons.Filled.MoreVert,
                                contentDescription = null,
                                tint = Gryonix.colors.accent,
                                modifier = Modifier.size(20.dp),
                            )
                        }
                        DropdownMenu(
                            expanded = menuOpen,
                            onDismissRequest = { menuOpen = false },
                        ) {
                            listOf(
                                R.string.containers_start to ContainerAction.START,
                                R.string.containers_stop to ContainerAction.STOP,
                                R.string.containers_restart to ContainerAction.RESTART,
                            ).forEach { (label, action) ->
                                DropdownMenuItem(
                                    text = { Text(stringResource(label)) },
                                    onClick = { menuOpen = false; onAction(action) }
                                )
                            }
                            HorizontalDivider()
                            listOf(
                                R.string.containers_logs to GroupSheetKind.LOG,
                                R.string.containers_update to GroupSheetKind.UPDATE,
                                R.string.containers_backup_now to GroupSheetKind.BACKUP_NOW,
                                R.string.containers_backup_plan to GroupSheetKind.PLAN,
                                R.string.containers_remove to GroupSheetKind.REMOVE,
                            ).forEach { (label, kind) ->
                                DropdownMenuItem(
                                    text = { Text(stringResource(label)) },
                                    onClick = { menuOpen = false; onLongVerb(kind) }
                                )
                            }
                        }
                    }
                }
            },
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        group.displayName,
                        style = MaterialTheme.typography.bodyLarge,
                        color = Gryonix.colors.label,
                    )
                    if (group.serviceID != null) {
                        Text(
                            stringResource(R.string.containers_installed_here),
                            style = MaterialTheme.typography.labelSmall,
                            color = Gryonix.colors.accent,
                            modifier = Modifier
                                .clip(RoundedCornerShape(percent = 50))
                                .background(Gryonix.colors.accent.copy(alpha = 0.12f))
                                .padding(horizontal = 8.dp, vertical = 2.dp),
                        )
                    }
                }
                Text(
                    stringResource(group.status.label),
                    style = MaterialTheme.typography.bodySmall,
                    color = group.status.tint(),
                )
            }
        }
        group.containers.forEach { container ->
            GroupedRow(
                onClick = { onInspect(container.name) },
                showDivider = container != group.containers.last(),
                trailing = { DisclosureChevron() },
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        container.name,
                        style = MaterialTheme.typography.bodyLarge,
                        color = Gryonix.colors.label,
                    )
                    Text(
                        buildString {
                            append(container.state)
                            if (container.health.isNotEmpty()) append(" (${container.health})")
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = Gryonix.colors.secondaryLabel,
                    )
                    if (container.ports.isNotEmpty()) {
                        Text(
                            container.ports,
                            style = MaterialTheme.typography.labelSmall,
                            color = Gryonix.colors.tertiaryLabel,
                        )
                    }
                }
            }
        }
    }
}

/** One container's detail */
@Composable
private fun DetailDialog(detail: ContainerDetail, onClose: () -> Unit) {
    IOSAlert(
        title = detail.container.name,
        onDismiss = onClose,
        actions = listOf(
            AlertAction(
                stringResource(R.string.containers_detail_close),
                preferred = true,
                onSelect = onClose,
            ),
        ),
    ) {
        SelectionContainer {
            Column(
                Modifier.heightIn(max = 380.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Field(stringResource(R.string.containers_detail_created), detail.createdAt)
                Field(
                    stringResource(R.string.containers_detail_restart_policy),
                    detail.restartPolicy,
                )
                if (detail.composeProject.isNotEmpty()) {
                    Field(
                        stringResource(R.string.containers_detail_compose),
                        "${detail.composeProject} · ${detail.composeService}"
                    )
                }
                Field(stringResource(R.string.containers_detail_command), detail.command)
                if (detail.mounts.isNotEmpty()) {
                    DetailHeading(stringResource(R.string.containers_detail_mounts))
                    detail.mounts.forEach { mount ->
                        Mono(
                            "${mount.displaySource} → ${mount.destination}" +
                                if (mount.isReadOnly) " (ro)" else ""
                        )
                    }
                }
                if (detail.environment.isNotEmpty()) {
                    DetailHeading(stringResource(R.string.containers_detail_environment))
                    detail.environment.forEach { variable ->
                        Mono(
                            "${variable.key}=" + if (variable.isSensitive) {
                                stringResource(R.string.containers_detail_hidden)
                            } else {
                                variable.value
                            }
                        )
                    }
                }
            }
        }
    }
}

/** A heading inside the detail alert */
@Composable
private fun DetailHeading(text: String) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelSmall,
        color = Gryonix.colors.secondaryLabel,
        modifier = Modifier.padding(top = 4.dp),
    )
}

@Composable
private fun Mono(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        fontFamily = FontFamily.Monospace,
        color = Gryonix.colors.label,
    )
}

@Composable
private fun Field(label: String, value: String) {
    if (value.isEmpty()) return
    Column {
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = Gryonix.colors.secondaryLabel,
        )
        Text(value, style = MaterialTheme.typography.bodySmall, color = Gryonix.colors.label)
    }
}

@Composable
private fun Note(text: String, isError: Boolean = false) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = if (isError) Gryonix.colors.danger else Gryonix.colors.secondaryLabel,
        modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
    )
}

@Composable
private fun Loading() {
    Row(
        Modifier.padding(horizontal = Metrics.listInset + 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CircularProgressIndicator(
            Modifier.size(16.dp),
            strokeWidth = 2.dp,
            color = Gryonix.colors.tertiaryLabel,
        )
        Text(
            stringResource(R.string.vpn_loading),
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.secondaryLabel,
        )
    }
}

/** The four answers the agent gives, in this app's words */
private val ContainerGroupStatus.label: Int
    get() = when (this) {
        ContainerGroupStatus.RUNNING -> R.string.containers_status_running
        ContainerGroupStatus.STOPPED -> R.string.containers_status_stopped
        ContainerGroupStatus.PARTIAL -> R.string.containers_status_partial
        ContainerGroupStatus.ERROR -> R.string.containers_status_error
        ContainerGroupStatus.UNKNOWN -> R.string.containers_status_unknown
    }

@Composable
private fun ContainerGroupStatus.tint() = when (this) {
    ContainerGroupStatus.RUNNING -> Gryonix.colors.success
    ContainerGroupStatus.ERROR -> Gryonix.colors.danger
    else -> Gryonix.colors.secondaryLabel
}
