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
import androidx.compose.material.icons.filled.MoreHoriz
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.draw.rotate
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.border
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import com.skaymer.gryonixnexus.app.ui.design.SectionHeader
import com.skaymer.gryonixnexus.agentcontrol.ContainerSummary
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
            if (only != null) item(key = "head-${server.id}") {
                SectionHeader(stringResource(R.string.tab_containers))
            } else item(key = "head-${server.id}") {
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
                        server.name,
                        style = MaterialTheme.typography.titleSmall,
                        color = Gryonix.colors.accent,
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
                        item(key = "groups-${server.id}") {
                            GroupBlocks(
                                serverID = server.id,
                                groups = state.inventory.groups,
                                busy = busy,
                                onAction = { key, action -> containers.control(server, key, action) },
                                onRename = { key, name -> containers.rename(server, key, name) },
                                onInspect = { name -> scope.launch { showing = containers.detail(server, name) } },
                                onLongVerb = { group, kind ->
                                    when (kind) {
                                        GroupSheetKind.UPDATE ->
                                            containers.start(server, group.key, GroupOperationKind.UPDATE)
                                        GroupSheetKind.BACKUP_NOW ->
                                            containers.start(server, group.key, GroupOperationKind.BACKUP)
                                        else -> sheet = GroupSheet(server, group, kind)
                                    }
                                },
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

/** One card: what this app installed, then what else runs */
@Composable
private fun GroupBlocks(
    serverID: String,
    groups: List<ContainerGroup>,
    busy: Set<String>,
    onAction: (String, ContainerAction) -> Unit,
    onInspect: (String) -> Unit,
    onLongVerb: (ContainerGroup, GroupSheetKind) -> Unit,
    onRename: (String, String) -> Unit,
) {
    var open by remember { mutableStateOf(setOf<String>()) }
    val titleOf = serviceTitles(serverID)
    val installed = groups.filter { it.serviceID != null }
    val found = groups.filter { it.serviceID == null }
    GroupedSection {
        listOf(R.string.containers_block_installed to installed, R.string.containers_block_found to found)
            .filter { it.second.isNotEmpty() }
            .forEach { (title, block) ->
                BlockHeader(stringResource(title), block.size)
                block.forEach { group ->
                    val isOpen = group.key in open
                    GroupRow(group, groupTitle(group, titleOf), isOpen, group.key in busy, { open = if (isOpen) open - group.key else open + group.key },
                        { onAction(group.key, it) }, { onLongVerb(group, it) })
                    if (isOpen) {
                        PendingTextRow(
                            label = stringResource(R.string.name_label),
                            saved = group.displayName,
                            placeholder = group.derivedName,
                            valid = { true },
                            onApply = { onRename(group.key, it.trim()) },
                        )
                        group.containers.forEach { ContainerRow(it) { onInspect(it.name) } }
                    }
                }
            }
    }
}

@Composable
private fun BlockHeader(title: String, count: Int) {
    GroupedRow {
        Text(title, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold,
            color = Gryonix.colors.secondaryLabel, modifier = Modifier.weight(1f))
        Text("$count", style = MaterialTheme.typography.bodySmall, color = Gryonix.colors.tertiaryLabel)
    }
}

/** A service's given name, unless the group has its own */
internal fun groupTitle(group: ContainerGroup, titleOf: (com.skaymer.gryonixnexus.catalog.ManagedService) -> String): String {
    val agentID = group.serviceID?.takeIf { !group.isRenamed } ?: return group.displayName
    val service = com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping.serviceIDs(listOf(agentID)).singleOrNull()
        ?.let { com.skaymer.gryonixnexus.catalog.ServiceRegistry.service(it) } ?: return group.displayName
    return titleOf(service).takeIf { it != service.displayName } ?: group.displayName
}

/** Chevron, status dot, name and kind, then the actions menu */
@Composable
private fun GroupRow(
    group: ContainerGroup,
    title: String,
    isOpen: Boolean,
    isBusy: Boolean,
    onToggle: () -> Unit,
    onAction: (ContainerAction) -> Unit,
    onLongVerb: (GroupSheetKind) -> Unit,
) {
    GroupedRow(
        onClick = onToggle,
        leading = {
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight, null,
                tint = Gryonix.colors.secondaryLabel,
                modifier = Modifier.size(22.dp).rotate(if (isOpen) 90f else 0f),
            )
        },
        trailing = {
            if (isBusy) {
                CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = Gryonix.colors.tertiaryLabel)
            } else {
                GroupMenu(onAction, onLongVerb)
            }
        },
    ) {
        Box(Modifier.size(9.dp).clip(CircleShape).background(group.status.tint()))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = Gryonix.colors.label)
            Text(
                stringResource(if (group.isComposeProject) R.string.containers_compose else R.string.containers_standalone),
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.secondaryLabel,
            )
        }
    }
}

/** The circled "⋯" with every group action */
@Composable
private fun GroupMenu(onAction: (ContainerAction) -> Unit, onLongVerb: (GroupSheetKind) -> Unit) {
    var menuOpen by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { menuOpen = true }, modifier = Modifier.size(32.dp)) {
            Box(
                Modifier.size(24.dp).border(1.5.dp, Gryonix.colors.accent, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.MoreHoriz, null, tint = Gryonix.colors.accent, modifier = Modifier.size(16.dp))
            }
        }
        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            listOf(
                R.string.containers_start to ContainerAction.START,
                R.string.containers_restart to ContainerAction.RESTART,
                R.string.containers_stop to ContainerAction.STOP,
            ).forEach { (label, action) ->
                DropdownMenuItem(text = { Text(stringResource(label)) }, onClick = { menuOpen = false; onAction(action) })
            }
            HorizontalDivider()
            listOf(
                R.string.containers_logs to GroupSheetKind.LOG,
                R.string.containers_backup_plan to GroupSheetKind.PLAN,
                R.string.containers_backup_now to GroupSheetKind.BACKUP_NOW,
                R.string.containers_update to GroupSheetKind.UPDATE,
                R.string.containers_remove to GroupSheetKind.REMOVE,
            ).forEach { (label, kind) ->
                DropdownMenuItem(text = { Text(stringResource(label)) }, onClick = { menuOpen = false; onLongVerb(kind) })
            }
        }
    }
}

/** One container under its open group */
@Composable
private fun ContainerRow(container: ContainerSummary, onOpen: () -> Unit) {
    GroupedRow(onClick = onOpen, modifier = Modifier.padding(start = 34.dp), trailing = { DisclosureChevron() }) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text(container.name, style = MaterialTheme.typography.bodyMedium, color = Gryonix.colors.label)
            Text(container.image, style = MaterialTheme.typography.labelSmall, color = Gryonix.colors.secondaryLabel,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (container.ports.isNotEmpty()) {
                Text(container.ports, style = MaterialTheme.typography.labelSmall, fontFamily = FontFamily.Monospace,
                    color = Gryonix.colors.secondaryLabel, maxLines = 1)
            }
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(container.state, style = MaterialTheme.typography.bodySmall, color = Gryonix.colors.secondaryLabel)
            if (container.health.isNotEmpty()) {
                Text(container.health, style = MaterialTheme.typography.labelSmall,
                    color = if (container.health == "healthy") Gryonix.colors.success else Gryonix.colors.warning)
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
        text,
        style = MaterialTheme.typography.labelLarge,
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
