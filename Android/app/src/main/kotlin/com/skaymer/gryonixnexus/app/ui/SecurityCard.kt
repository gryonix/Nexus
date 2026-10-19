package com.skaymer.gryonixnexus.app.ui

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
    LaunchedEffect(deployment.id) {
        security.reset()
        security.load(deployment)
        security.loadSshAccess(deployment)
    }

    GroupedSection(
        header = stringResource(R.string.security_title),
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

    SshAccessCard(deployment, security, state)
}

@Composable
private fun SshAccessCard(
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
            color = if (healthy) Gryonix.colors.accent else Gryonix.colors.warning,
        )
    }

    StatRow(stringResource(R.string.security_attacks_24h), status.alertsLast24h.toString())
    if (status.communityBlocklistIps > 0) {
        StatRow(
            stringResource(R.string.security_community_blocklist),
            stringResource(
                R.string.security_addresses,
                SecurityViewModel.compact(status.communityBlocklistIps.toLong()),
            ),
        )
    }
    if (status.localBans > 0) {
        StatRow(stringResource(R.string.security_blocked_now), status.localBans.toString())
    }
    if (status.packetsDropped > 0) {
        StatRow(
            stringResource(R.string.security_packets_dropped),
            SecurityViewModel.compact(status.packetsDropped),
        )
    }

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

    SecurityActions(deployment, security, state, engineRunning = status.engineRunning, present = true)
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

    ActionRow(
        text = stringResource(R.string.security_action_reload),
        onClick = {
            security.load(deployment)
            security.loadSshAccess(deployment)
        },
    )
    ActionRow(
        text = stringResource(R.string.security_action_update),
        onClick = { run(AgentSecurityOperations.Action.UPDATE) },
    )
    ActionRow(
        text = stringResource(R.string.security_action_restart),
        onClick = { run(AgentSecurityOperations.Action.RESTART) },
    )
    if (engineRunning) {
        ActionRow(
            text = stringResource(R.string.security_action_stop),
            onClick = { run(AgentSecurityOperations.Action.STOP) },
            danger = true,
        )
    } else {
        ActionRow(
            text = stringResource(R.string.security_action_start),
            onClick = { run(AgentSecurityOperations.Action.START) },
        )
    }
    ActionRow(
        text = stringResource(R.string.security_action_remove),
        onClick = { run(AgentSecurityOperations.Action.REMOVE) },
        danger = true,
        showDivider = false,
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
