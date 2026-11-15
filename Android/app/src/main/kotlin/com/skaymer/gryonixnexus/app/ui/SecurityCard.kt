package com.skaymer.gryonixnexus.app.ui

import androidx.compose.material.icons.filled.Security
import com.skaymer.gryonixnexus.app.ui.design.IOSSwitch
import com.skaymer.gryonixnexus.servercontrol.SshUserAccess
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.material.icons.filled.GppGood
import androidx.compose.material.icons.filled.GppMaybe
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.outlined.PauseCircle
import androidx.compose.material.icons.outlined.PlayCircle
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import com.skaymer.gryonixnexus.app.ui.design.TileAction
import com.skaymer.gryonixnexus.app.ui.design.TileActionGroup
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.style.TextOverflow
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.agentcontrol.AgentSecurityOperations
import com.skaymer.gryonixnexus.app.security.SecurityScreenState
import com.skaymer.gryonixnexus.app.security.SecurityViewModel
import com.skaymer.gryonixnexus.servercontrol.SshUsers
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.RefreshButton
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostSecurityStatus
import com.skaymer.gryonixnexus.servercontrol.SshPasswordAccess

@Composable
fun SecurityCard(
    deployment: Deployment,
    security: SecurityViewModel,
    /** Where the fleet-wide rules template lives — see `SecurityRulesTemplate` */
    settings: SettingsStore,
) {
    val state by security.state.collectAsState()
    PleaseWaitDialog(
        state.busy || state.runningAction != null || state.listBusy,
        detail = state.actionProgress,
    )
    LaunchedEffect(deployment.id) { security.loadIfStale(deployment) }

    Column(verticalArrangement = GroupedSpacing) {
        SecurityStatusSection(deployment, security, state, settings)
        SshAccessCard(deployment, security, state)
    }
}

@Composable
internal fun SecurityStatusSection(
    deployment: Deployment,
    security: SecurityViewModel,
    state: SecurityScreenState,
    settings: SettingsStore,
    onPage: Boolean = false,
) {
    GroupedSection(
        header = if (onPage) null else stringResource(R.string.security_title),
        note = stringResource(R.string.security_hint),
        footer = stringResource(R.string.security_absent_hint)
            .takeIf { state.hasAnswered && !state.statusUnread && state.status?.isPresent != true },
        onRefresh = { security.refreshAll(deployment) },
        refreshDescription = stringResource(R.string.refresh_this_again),
        refreshing = state.reading || state.readingSsh,
    ) {
        val status = state.status
        when {
            !state.hasAnswered -> GroupedRow(
                trailing = {
                    CircularProgressIndicator(
                        Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = Gryonix.colors.secondaryLabel,
                    )
                },
            ) { RowLabel(stringResource(R.string.security_title)) }

            state.statusUnread -> GroupedRow(
                trailing = {
                    RefreshButton(
                        contentDescription = stringResource(R.string.refresh_security_again),
                        onClick = { security.load(deployment) },
                        busy = state.reading,
                    )
                },
                showDivider = false,
            ) {
                RowLabel(
                    stringResource(R.string.security_title),
                    stringResource(R.string.security_could_not_read),
                )
            }

            status == null || !status.isPresent -> {
                GroupedRow(
                    trailing = {
                        Text(
                            stringResource(R.string.security_not_set_up),
                            style = MaterialTheme.typography.bodyLarge,
                            color = Gryonix.colors.secondaryLabel,
                        )
                    },
                ) { RowLabel(stringResource(R.string.security_title)) }
                SecurityActions(deployment, security, state, engineRunning = false, present = false)
            }

            else -> Present(status, deployment, security, state, settings)
        }
    }
    val present = state.status?.takeIf { it.isPresent && !state.statusUnread }
    if (present != null) {
        GroupedSection(header = stringResource(R.string.security_actions_title)) {
            SecurityActions(deployment, security, state, engineRunning = present.engineRunning, present = true)
        }
    }
}

@Composable
internal fun SshAccessCard(
    deployment: Deployment,
    security: SecurityViewModel,
    state: SecurityScreenState,
) {
    var confirmingClose by remember { mutableStateOf(false) }
    var confirmingOpen by remember { mutableStateOf(false) }
    val access = state.sshAccess
    val user = access?.loginUser?.takeIf { it.isNotEmpty() } ?: deployment.entry.user

    GroupedSection(
        header = stringResource(R.string.security_ssh_title),
        onRefresh = { security.loadSshAccess(deployment) },
        refreshDescription = stringResource(R.string.refresh_ssh_again),
        refreshing = state.readingSsh,
        footer = when {
            access == null -> stringResource(R.string.security_ssh_hint_reading)
            !access.isKnown -> stringResource(R.string.security_ssh_hint_unknown)
            access.isOutranked -> stringResource(R.string.security_ssh_hint_outranked)
            access.isClosed -> stringResource(R.string.security_ssh_hint_closed)
            !access.appKeyPresent -> stringResource(R.string.security_ssh_hint_needs_key)
            else -> stringResource(R.string.security_ssh_hint_open, user)
        },
    ) {
        when {
            access == null -> GroupedRow(
                trailing = {
                    CircularProgressIndicator(
                        Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = Gryonix.colors.secondaryLabel,
                    )
                },
            ) { RowLabel(stringResource(R.string.security_ssh_password_login)) }

            !access.isKnown -> GroupedRow(
                trailing = {
                    Text(
                        stringResource(R.string.security_ssh_unknown),
                        style = MaterialTheme.typography.bodyLarge,
                        color = Gryonix.colors.secondaryLabel,
                    )
                },
            ) { RowLabel(stringResource(R.string.security_ssh_password_login)) }

            else -> {
                GroupedRow(
                    trailing = {
                        Text(
                            user,
                            style = MaterialTheme.typography.bodySmall,
                            color = Gryonix.colors.tertiaryLabel,
                        )
                    },
                ) {
                    Text(
                        stringResource(
                            if (access.isClosed) {
                                R.string.security_ssh_key_only
                            } else {
                                R.string.security_ssh_open
                            },
                        ),
                        style = MaterialTheme.typography.bodyLarge,
                        color = if (access.isClosed) Gryonix.colors.accent else Gryonix.colors.warning,
                    )
                }
                (state.failure ?: access.detail.takeIf { it.isNotEmpty() })?.let { line ->
                    GroupedRow(showDivider = false) {
                        Text(
                            line,
                            style = MaterialTheme.typography.bodySmall,
                            color = if (access.isClosed && state.failure == null) {
                                Gryonix.colors.secondaryLabel
                            } else {
                                Gryonix.colors.warning
                            },
                        )
                    }
                }
                when {
                    state.busy -> GroupedRow(
                        trailing = {
                            CircularProgressIndicator(
                                Modifier.size(16.dp),
                                strokeWidth = 2.dp,
                                color = Gryonix.colors.secondaryLabel,
                            )
                        },
                        showDivider = false,
                    ) { RowLabel(stringResource(R.string.security_ssh_working)) }

                    access.isClosed -> ActionRow(
                        text = stringResource(R.string.security_ssh_allow),
                        onClick = { confirmingOpen = true },
                        showDivider = false,
                    )

                    access.canClose -> ActionRow(
                        text = stringResource(R.string.security_ssh_turn_off),
                        onClick = { confirmingClose = true },
                        danger = true,
                        showDivider = false,
                    )

                    else -> ActionRow(
                        text = stringResource(R.string.security_ssh_add_key),
                        onClick = { security.grantAppKey(deployment) },
                        showDivider = false,
                    )
                }
            }
        }
    }

    if (confirmingClose) {
        ConfirmAlert(
            title = stringResource(R.string.security_ssh_close_title),
            message = stringResource(R.string.security_ssh_close_message, user),
            confirm = stringResource(R.string.security_ssh_close_confirm),
            destructive = true,
            onConfirm = {
                confirmingClose = false
                security.setSshPasswordLogin(deployment, allowPasswords = false)
            },
            onCancel = { confirmingClose = false },
        )
    }
    if (confirmingOpen) {
        ConfirmAlert(
            title = stringResource(R.string.security_ssh_open_title),
            message = stringResource(R.string.security_ssh_open_message),
            confirm = stringResource(R.string.security_ssh_open_confirm),
            destructive = true,
            onConfirm = {
                confirmingOpen = false
                security.setSshPasswordLogin(deployment, allowPasswords = true)
            },
            onCancel = { confirmingOpen = false },
        )
    }
}

@Composable
private fun Present(
    status: HostSecurityStatus,
    deployment: Deployment,
    security: SecurityViewModel,
    state: SecurityScreenState,
    settings: SettingsStore,
) {
    val healthy = status.isHealthy
    GroupedRow(
        leading = {
            Icon(
                if (healthy) Icons.Filled.GppGood else Icons.Filled.GppMaybe,
                contentDescription = null,
                tint = if (healthy) Gryonix.colors.success else Gryonix.colors.warning,
                modifier = Modifier.size(22.dp),
            )
        },
        trailing = {
            if (status.engineVersion.isNotEmpty()) {
                Text(
                    "CrowdSec ${status.engineVersion}",
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.tertiaryLabel,
                )
            }
        },
    ) {
        Text(
            stringResource(
                if (healthy) R.string.security_protecting else R.string.security_degraded,
            ),
            style = MaterialTheme.typography.bodyLarge,
            color = Gryonix.colors.label,
            modifier = Modifier.weight(1f),
        )
    }

    StatGrid(
        buildList {
            add(status.alertsLast24h.toString() to stringResource(R.string.security_attacks_24h))
            if (status.communityBlocklistIps > 0) {
                add(
                    SecurityViewModel.compact(status.communityBlocklistIps.toLong()) to
                        stringResource(R.string.security_community_blocklist)
                )
            }
            if (status.localBans > 0) {
                add(status.localBans.toString() to stringResource(R.string.security_blocked_now))
            }
            if (status.packetsDropped > 0) {
                add(SecurityViewModel.compact(status.packetsDropped) to stringResource(R.string.security_packets_dropped))
            }
        }
    )

    SecurityBlocklistSection(deployment, security, state)

    var showingAutoRules by remember(deployment.id) { mutableStateOf(false) }
    LaunchedEffect(deployment.id) { security.loadAutoRules(deployment) }
    ValueRow(
        title = stringResource(R.string.security_auto_row),
        value = stringResource(
            if (state.autoRules?.isOn == true) R.string.security_auto_state_on
            else R.string.security_auto_state_off,
        ),
        onClick = { showingAutoRules = true },
        leading = {
            Icon(Icons.Filled.Shield, contentDescription = null, modifier = Modifier.size(22.dp))
        },
    )
    if (showingAutoRules) {
        SecurityAutoRulesSheet(
            deployment = deployment,
            security = security,
            store = settings,
            onClose = { showingAutoRules = false },
        )
    }

    if (status.recentBans.isNotEmpty()) {
        var expanded by remember { mutableStateOf(false) }
        var selecting by remember { mutableStateOf(false) }
        val selected = remember { mutableStateListOf<String>() }
        GroupedRow(
            onClick = { expanded = !expanded },
            trailing = { DisclosureChevron() },
            showDivider = false,
        ) { RowLabel(stringResource(R.string.security_recent_attempts)) }
        AnimatedVisibility(expanded) {
            Column {
                status.recentBans.forEach { ban ->
                    AttemptRow(
                        ban = ban,
                        deployment = deployment,
                        security = security,
                        busy = state.listBusy,
                        selecting = selecting,
                        picked = selected.contains(ban.ip),
                        onPick = {
                            if (selected.contains(ban.ip)) selected.remove(ban.ip)
                            else selected.add(ban.ip)
                        },
                    )
                }
                if (selecting) {
                    ActionRow(
                        text = stringResource(R.string.security_select_all),
                        enabled = selected.size != status.recentBans.size,
                        showDivider = true,
                        onClick = {
                            selected.clear()
                            selected.addAll(status.recentBans.map { it.ip })
                        },
                    )
                    ActionRow(
                        text = stringResource(R.string.security_block_selected, selected.size),
                        danger = true,
                        enabled = selected.isNotEmpty() && !state.listBusy,
                        showDivider = true,
                        onClick = {
                            security.setBans(deployment, selected.toList(), DEFAULT_BAN_SECONDS)
                            selecting = false
                            selected.clear()
                        },
                    )
                    ActionRow(
                        text = stringResource(R.string.security_select_cancel),
                        showDivider = false,
                        onClick = { selecting = false; selected.clear() },
                    )
                } else {
                    ActionRow(
                        text = stringResource(R.string.security_select),
                        showDivider = false,
                        onClick = { selecting = true },
                    )
                }
            }
        }
    }
}

@Composable
private fun SecurityActions(
    deployment: Deployment,
    security: SecurityViewModel,
    state: SecurityScreenState,
    engineRunning: Boolean,
    present: Boolean,
) {
    var confirming by remember { mutableStateOf<AgentSecurityOperations.Action?>(null) }
    val running = state.runningAction

    if (running != null) {
        GroupedRow(
            showDivider = false,
            trailing = {
                CircularProgressIndicator(
                    Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = Gryonix.colors.secondaryLabel,
                )
            },
        ) {
            Column {
                Text(
                    stringResource(runningTitle(running)),
                    style = MaterialTheme.typography.bodyLarge,
                    color = Gryonix.colors.label,
                )
                if (state.actionProgress.isNotEmpty()) {
                    Text(
                        state.actionProgress,
                        style = MaterialTheme.typography.bodySmall,
                        color = Gryonix.colors.tertiaryLabel,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
        return
    }

    fun run(action: AgentSecurityOperations.Action) {
        if (action.isDestructive) confirming = action else security.runAction(deployment, action)
    }

    if (!present) {
        ActionRow(
            text = stringResource(R.string.security_action_install),
            onClick = { run(AgentSecurityOperations.Action.INSTALL) },
            showDivider = false,
        )
        return
    }

    TileActionGroup(
        listOf(
            TileAction(stringResource(R.string.security_tile_update), Icons.Filled.Sync, {
                run(AgentSecurityOperations.Action.UPDATE)
            }),
            TileAction(stringResource(R.string.security_tile_restart), Icons.Filled.Refresh, {
                run(AgentSecurityOperations.Action.RESTART)
            }),
            if (engineRunning) {
                TileAction(stringResource(R.string.security_tile_stop), Icons.Outlined.PauseCircle, {
                    run(AgentSecurityOperations.Action.STOP)
                }, danger = true)
            } else {
                TileAction(stringResource(R.string.security_tile_start), Icons.Outlined.PlayCircle, {
                    run(AgentSecurityOperations.Action.START)
                })
            },
            TileAction(stringResource(R.string.security_tile_remove), Icons.Outlined.Delete, {
                run(AgentSecurityOperations.Action.REMOVE)
            }, danger = true),
        ),
        Modifier.padding(16.dp),
    )

    confirming?.let { action ->
        val removing = action == AgentSecurityOperations.Action.REMOVE
        ConfirmAlert(
            title = stringResource(
                if (removing) R.string.security_confirm_remove_title
                else R.string.security_confirm_stop_title,
            ),
            message = stringResource(
                if (removing) R.string.security_confirm_remove_message
                else R.string.security_confirm_stop_message,
            ),
            confirm = stringResource(
                if (removing) R.string.security_action_remove_short
                else R.string.security_action_stop_short,
            ),
            destructive = true,
            onConfirm = {
                security.runAction(deployment, action)
                confirming = null
            },
            onCancel = { confirming = null },
        )
    }
}

private fun runningTitle(action: AgentSecurityOperations.Action): Int = when (action) {
    AgentSecurityOperations.Action.START -> R.string.security_running_start
    AgentSecurityOperations.Action.STOP -> R.string.security_running_stop
    AgentSecurityOperations.Action.RESTART -> R.string.security_running_restart
    AgentSecurityOperations.Action.UPDATE -> R.string.security_running_update
    AgentSecurityOperations.Action.INSTALL -> R.string.security_running_install
    AgentSecurityOperations.Action.REMOVE -> R.string.security_running_remove
}

/** The numbers as tiles, two to a line */
@Composable
private fun StatGrid(stats: List<Pair<String, String>>) {
    GroupedRow {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            stats.chunked(2).forEach { line ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    line.forEach { (value, title) ->
                        Column(Modifier.weight(1f)) {
                            Text(value, style = MaterialTheme.typography.titleLarge, color = Gryonix.colors.label)
                            Text(title, style = MaterialTheme.typography.labelSmall, color = Gryonix.colors.secondaryLabel)
                        }
                    }
                    if (line.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun StatRow(title: String, value: String) {
    GroupedRow(
        trailing = {
            Text(
                value,
                style = MaterialTheme.typography.bodyLarge,
                color = Gryonix.colors.secondaryLabel,
            )
        },
    ) { RowLabel(title) }
}

@Composable
private fun AttemptRow(
    ban: HostSecurityStatus.Ban,
    deployment: Deployment,
    security: SecurityViewModel,
    busy: Boolean,
    selecting: Boolean,
    picked: Boolean,
    onPick: () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    GroupedRow(
        showDivider = false,
        onClick = if (selecting) onPick else null,
        onLongClick = if (selecting || busy) null else { { menu = true } },
        leading = if (!selecting) null else {
            {
                Icon(
                    if (picked) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                    contentDescription = null,
                    tint = if (picked) Gryonix.colors.accent else Gryonix.colors.secondaryLabel,
                )
            }
        },
        trailing = {
            AttemptMenu(
                shown = menu,
                ip = ban.ip,
                onDismiss = { menu = false },
                onBan = { value, seconds ->
                    menu = false
                    security.setBan(deployment, banned = true, value = value,
                                    durationSeconds = seconds)
                },
                onAllow = {
                    menu = false
                    security.setAllowed(deployment, allowed = true, value = ban.ip)
                },
            )
        },
    ) {
        Column {
            Text(
                listOf(SecurityViewModel.flag(ban.country), ban.ip)
                    .filter { it.isNotEmpty() }
                    .joinToString(" "),
                style = MaterialTheme.typography.bodyMedium,
                color = Gryonix.colors.label,
            )
            Text(
                HostSecurityStatus.Scenario(ban.scenario, 0).readableName,
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.tertiaryLabel,
            )
        }
    }
}

/** What CrowdSec itself bans for when nothing says otherwise */
private const val DEFAULT_BAN_SECONDS = 4L * 3600

const val UNTIL_LIFTED_SECONDS = 10L * 365 * 24 * 3600

@Composable
private fun AttemptMenu(
    shown: Boolean,
    ip: String,
    onDismiss: () -> Unit,
    onBan: (String, Long) -> Unit,
    onAllow: () -> Unit,
) {
    DropdownMenu(expanded = shown, onDismissRequest = onDismiss) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.security_block_4h)) },
            onClick = { onBan(ip, DEFAULT_BAN_SECONDS) },
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.security_block_24h)) },
            onClick = { onBan(ip, 24L * 3600) },
        )
        DropdownMenuItem(
            text = { Text(stringResource(R.string.security_block_until_lifted)) },
            onClick = { onBan(ip, UNTIL_LIFTED_SECONDS) },
        )
        subnetOf(ip)?.let { subnet ->
            DropdownMenuItem(
                text = { Text(stringResource(R.string.security_block_subnet, subnet)) },
                onClick = { onBan(subnet, 24L * 3600) },
            )
        }
        DropdownMenuItem(
            text = { Text(stringResource(R.string.security_never_block)) },
            onClick = { onAllow() },
        )
    }
}

internal fun subnetOf(address: String): String? {
    if (address.contains(":")) {
        val groups = address.split(":")
        if (groups.size < 4) return null
        val prefix = groups.take(4)
        if (prefix.any { it.isEmpty() || it.toIntOrNull(16) == null }) return null
        return prefix.joinToString(":") + "::/64"
    }
    val octets = address.split(".")
    if (octets.size != 4 || octets.any { it.toIntOrNull()?.let { n -> n in 0..255 } != true }) {
        return null
    }
    return "${octets[0]}.${octets[1]}.${octets[2]}.0/24"
}

/** The intrusion defence on a page of its own */
@Composable
fun CrowdSecPage(deployment: Deployment, security: SecurityViewModel, settings: SettingsStore) {
    val state by security.state.collectAsState()
    PleaseWaitDialog(state.busy || state.runningAction != null || state.listBusy, detail = state.actionProgress)
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(GroupedContentPadding),
        verticalArrangement = GroupedSpacing,
    ) { SecurityStatusSection(deployment, security, state, settings, onPage = true) }
}

/** SSH password login on a page of its own */
@Composable
fun SshAccessPage(deployment: Deployment, security: SecurityViewModel) {
    val state by security.state.collectAsState()
    var confirming by remember(deployment.id) { mutableStateOf<KeyOnlyChange?>(null) }
    LaunchedEffect(deployment.id) { if (state.sshUsers == null) security.loadSshUsers(deployment) }
    PleaseWaitDialog(state.busy || state.workingOnSshUsers, detail = state.actionProgress)
    val answer = state.sshUsers
    val working = state.workingOnSshUsers
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(GroupedContentPadding),
        verticalArrangement = GroupedSpacing,
    ) {
        SshEveryoneSection(answer, working) { confirming = it }
        SshAccountsSection(answer, working, state.busy, onAddKey = { security.grantAppKey(deployment) }) {
            confirming = it
        }
    }
    confirming?.let { change ->
        ConfirmAlert(
            title = stringResource(if (change.opening) R.string.ssh_users_open_title else R.string.ssh_users_close_title),
            message = when {
                change.opening -> stringResource(R.string.ssh_users_open_message)
                change.everyone -> stringResource(R.string.ssh_users_close_everyone_message, deployment.entry.user)
                else -> stringResource(R.string.ssh_users_close_one_message, change.account)
            },
            confirm = stringResource(if (change.opening) R.string.ssh_users_open_confirm else R.string.ssh_users_close_confirm),
            destructive = true,
            onConfirm = {
                confirming = null
                security.setKeyOnlyUsers(deployment, change.everyone, change.users)
            },
            onCancel = { confirming = null },
        )
    }
}

/** Password login for every account at once */
@Composable
private fun SshEveryoneSection(answer: SshUsers?, working: Boolean, onChange: (KeyOnlyChange) -> Unit) {
    GroupedSection(
        header = stringResource(R.string.ssh_users_everyone_header),
        note = stringResource(R.string.ssh_users_everyone_note),
        footer = answer?.detail?.takeIf { it.isNotEmpty() },
    ) {
        GroupedRow(
            showDivider = false,
            leading = {
                Icon(Icons.Filled.Security, contentDescription = null, modifier = Modifier.size(22.dp))
            },
            trailing = {
                IOSSwitch(
                    checked = answer?.isClosedForEveryone ?: false,
                    onCheckedChange = { wanted ->
                        onChange(KeyOnlyChange(everyone = wanted, users = emptyList(), opening = !wanted, account = ""))
                    },
                    enabled = !working && answer?.isKnown == true,
                    onColor = Gryonix.colors.success,
                )
            },
        ) { RowLabel(stringResource(R.string.ssh_users_everyone)) }
    }
}

/** One switch per account that may log in */
@Composable
private fun SshAccountsSection(
    answer: SshUsers?,
    working: Boolean,
    busy: Boolean,
    onAddKey: () -> Unit,
    onChange: (KeyOnlyChange) -> Unit,
) {
    GroupedSection(
        header = stringResource(R.string.ssh_users_accounts_header),
        note = stringResource(R.string.ssh_users_accounts_note),
        footer = stringResource(R.string.ssh_users_all_closed).takeIf { answer?.isClosedForEveryone == true },
    ) {
        when {
            answer == null -> GroupedRow(
                showDivider = false,
                trailing = {
                    CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp, color = Gryonix.colors.secondaryLabel)
                },
            ) { RowLabel(stringResource(R.string.ssh_users_accounts_header)) }
            !answer.isKnown -> GroupedRow(showDivider = false) {
                RowLabel(stringResource(R.string.ssh_users_unknown))
            }
            answer.users.isEmpty() -> GroupedRow(showDivider = false) {
                RowLabel(stringResource(R.string.ssh_users_none))
            }
            else -> {
                val addKey = answer.host.isKnown && !answer.host.appKeyPresent
                answer.users.forEach { user ->
                    SshUserRow(
                        user = user,
                        enabled = !working && user.isKnown && !(user.wouldLockOut && !user.isClosed) &&
                            !answer.isClosedForEveryone,
                        showDivider = user != answer.users.last() || addKey,
                    ) { wanted ->
                        val names = answer.closedNames.toMutableSet()
                        if (wanted) names.add(user.name) else names.remove(user.name)
                        onChange(KeyOnlyChange(false, names.sorted(), opening = !wanted, account = user.name))
                    }
                }
                if (addKey) {
                    ActionRow(
                        text = stringResource(R.string.ssh_users_add_key),
                        onClick = onAddKey,
                        enabled = !busy,
                        showDivider = false,
                    )
                }
            }
        }
    }
}

/** What the tapped switch would do */
private data class KeyOnlyChange(
    val everyone: Boolean,
    val users: List<String>,
    val opening: Boolean,
    val account: String,
)

@Composable
private fun SshUserRow(user: SshUserAccess, enabled: Boolean, showDivider: Boolean, onToggle: (Boolean) -> Unit) {
    val caption = stringResource(
        when {
            !user.isKnown -> R.string.ssh_user_unknown
            user.isLoginUser -> R.string.ssh_user_login
            user.wouldLockOut -> R.string.ssh_user_no_key
            user.isClosed -> R.string.ssh_user_closed
            else -> R.string.ssh_user_open
        }
    )
    GroupedRow(
        showDivider = showDivider,
        trailing = {
            IOSSwitch(checked = user.isClosed, onCheckedChange = onToggle, enabled = enabled, onColor = Gryonix.colors.success)
        },
    ) {
        Column(Modifier.weight(1f)) {
            Text(user.name, style = MaterialTheme.typography.bodyLarge, fontFamily = FontFamily.Monospace, color = Gryonix.colors.label)
            Text(
                caption,
                style = MaterialTheme.typography.bodySmall,
                color = if (user.wouldLockOut) Gryonix.colors.warning else Gryonix.colors.secondaryLabel,
            )
        }
    }
}
