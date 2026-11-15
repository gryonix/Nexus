package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ListAlt
import androidx.compose.material.icons.filled.GppGood
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material.icons.outlined.ViewInAr
import androidx.compose.material.icons.outlined.GppBad
import androidx.compose.material.icons.outlined.GppMaybe
import androidx.compose.material.icons.outlined.HelpOutline
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.LockOpen
import androidx.compose.material.icons.outlined.ManageSearch
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.agentcontrol.AgentSecurityOperations
import com.skaymer.gryonixnexus.app.security.SecurityViewModel
import com.skaymer.gryonixnexus.app.servers.HostActionsViewModel
import com.skaymer.gryonixnexus.app.servers.LockdownRead
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSwitch
import com.skaymer.gryonixnexus.app.ui.design.RefreshButton
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** A row that opens a page, with its icon */
@Composable
fun NavRow(icon: ImageVector, title: String, onClick: () -> Unit, showDivider: Boolean = true) {
    GroupedRow(
        onClick = onClick,
        showDivider = showDivider,
        leading = { Icon(icon, contentDescription = null, modifier = Modifier.size(22.dp)) },
        trailing = { DisclosureChevron() },
    ) { RowLabel(title) }
}

/** Logins, configuration, devices and the server system */
@Composable
fun GeneralLinks(
    onLogins: () -> Unit,
    onConfiguration: () -> Unit,
    onSystem: (() -> Unit)?,
) {
    GroupedSection {
        NavRow(Icons.Outlined.Key, stringResource(R.string.general_logins), onLogins)
        NavRow(Icons.Outlined.ManageSearch, stringResource(R.string.general_configuration), onConfiguration,
            showDivider = onSystem != null)
        onSystem?.let { NavRow(Icons.Outlined.ViewInAr, stringResource(R.string.system_page_title), it, showDivider = false) }
    }
}

@Composable
fun AgentLink(onOpen: () -> Unit) {
    GroupedSection {
        NavRow(Icons.Outlined.Memory, stringResource(R.string.general_agent), onOpen, showDivider = false)
    }
}

/** Panel guard, intrusion defence and SSH access, one row each */
@Composable
fun SecuritySummary(
    deployment: Deployment,
    security: SecurityViewModel,
    actions: HostActionsViewModel,
    onLockdown: () -> Unit,
    onCrowdSec: () -> Unit,
    onSsh: () -> Unit,
) {
    val state by security.state.collectAsState()
    val hostState by actions.state.collectAsState()
    val hasGuard = remember(deployment) { HostActionsViewModel.hasAdminLockdown(deployment) }
    LaunchedEffect(deployment.id) { security.loadIfStale(deployment) }
    LaunchedEffect(deployment.id, hasGuard) { if (hasGuard) actions.refreshLockdownIfStale(deployment) }

    GroupedSection(
        header = stringResource(R.string.security_title),
        note = stringResource(R.string.security_hint),
        onRefresh = {
            security.refreshAll(deployment)
            if (hasGuard) actions.refreshLockdown(deployment)
        },
        refreshDescription = stringResource(R.string.refresh_this_again),
        refreshing = state.reading || state.readingSsh || hostState.lockdown is LockdownRead.Loading,
    ) {
        if (hasGuard) LockdownRow(deployment, actions, onLockdown)
        CrowdSecRow(deployment, security, onCrowdSec)
        SshRow(deployment, security, onSsh, showDivider = false)
    }
}

@Composable
private fun LockdownRow(deployment: Deployment, actions: HostActionsViewModel, onOpen: () -> Unit) {
    val state by actions.state.collectAsState()
    val read = state.lockdown
    val on = (read as? LockdownRead.Loaded)?.state?.isActive
    SecurityRow(
        icon = Icons.Outlined.Security,
        tint = if (on == true) Gryonix.colors.success else Gryonix.colors.secondaryLabel,
        title = stringResource(R.string.actions_lockdown),
        subtitle = stringResource(R.string.actions_lockdown_short),
        status = if (read is LockdownRead.Failed) stringResource(R.string.security_could_not_read) else null,
        refreshDescription = stringResource(R.string.refresh_lockdown_again),
        refreshing = read is LockdownRead.Loading,
        onRefresh = { actions.refreshLockdown(deployment) },
        checked = on,
        onToggle = { actions.setLockdown(deployment, it) },
        onOpen = onOpen,
    )
}

@Composable
private fun CrowdSecRow(deployment: Deployment, security: SecurityViewModel, onOpen: () -> Unit) {
    val state by security.state.collectAsState()
    var confirmingStop by remember(deployment.id) { mutableStateOf(false) }
    val status = state.status
    val (icon, tint) = when {
        state.statusUnread -> Icons.Outlined.HelpOutline to Gryonix.colors.warning
        status == null -> Icons.Outlined.Shield to Gryonix.colors.secondaryLabel
        !status.isPresent -> Icons.Outlined.GppBad to Gryonix.colors.secondaryLabel
        status.isHealthy -> Icons.Filled.GppGood to Gryonix.colors.success
        else -> Icons.Outlined.GppMaybe to Gryonix.colors.warning
    }
    SecurityRow(
        icon = icon,
        tint = tint,
        title = stringResource(R.string.security_title),
        status = when {
            state.statusUnread -> stringResource(R.string.security_could_not_read)
            status != null && !status.isPresent -> stringResource(R.string.security_row_not_set_up)
            status != null && !status.isHealthy -> stringResource(R.string.security_row_degraded)
            else -> null
        },
        refreshDescription = stringResource(R.string.refresh_security_again),
        refreshing = state.reading,
        onRefresh = { security.load(deployment) },
        checked = status?.takeIf { it.isPresent }?.engineRunning,
        enabled = state.runningAction == null,
        onToggle = { wanted ->
            if (wanted) security.runAction(deployment, AgentSecurityOperations.Action.START) else confirmingStop = true
        },
        onOpen = onOpen,
    )
    if (confirmingStop) {
        ConfirmAlert(
            title = stringResource(R.string.security_confirm_stop_title),
            message = stringResource(R.string.security_confirm_stop_message),
            confirm = stringResource(R.string.security_action_stop_short),
            destructive = true,
            onConfirm = {
                confirmingStop = false
                security.runAction(deployment, AgentSecurityOperations.Action.STOP)
            },
            onCancel = { confirmingStop = false },
        )
    }
}

@Composable
private fun SshRow(deployment: Deployment, security: SecurityViewModel, onOpen: () -> Unit, showDivider: Boolean) {
    val state by security.state.collectAsState()
    var confirmingClose by remember(deployment.id) { mutableStateOf(false) }
    var confirmingOpen by remember(deployment.id) { mutableStateOf(false) }
    val access = state.sshAccess?.takeIf { it.isKnown }
    val unread = state.sshAccess?.isKnown == false
    val user = access?.loginUser?.takeIf { it.isNotEmpty() } ?: deployment.entry.user
    SecurityRow(
        icon = when (access?.isClosed) {
            true -> Icons.Filled.Security
            false -> Icons.Outlined.LockOpen
            null -> Icons.Outlined.Shield
        },
        tint = when {
            access == null -> if (unread) Gryonix.colors.warning else Gryonix.colors.secondaryLabel
            access.isClosed -> Gryonix.colors.success
            else -> Gryonix.colors.warning
        },
        title = stringResource(R.string.security_ssh_title),
        status = if (unread) stringResource(R.string.security_could_not_read) else null,
        refreshDescription = stringResource(R.string.refresh_ssh_again),
        refreshing = state.readingSsh,
        onRefresh = { security.loadSshAccess(deployment) },
        checked = access?.isClosed,
        enabled = !state.busy && (access?.isClosed == true || access?.canClose == true),
        onToggle = { keyOnly -> if (keyOnly) confirmingClose = true else confirmingOpen = true },
        onOpen = onOpen,
        showDivider = showDivider,
    )
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
private fun SecurityRow(
    icon: ImageVector,
    tint: Color,
    title: String,
    subtitle: String? = null,
    status: String?,
    refreshDescription: String,
    refreshing: Boolean,
    onRefresh: () -> Unit,
    checked: Boolean?,
    enabled: Boolean = true,
    onToggle: (Boolean) -> Unit,
    onOpen: () -> Unit,
    showDivider: Boolean = true,
) {
    GroupedRow(
        onClick = onOpen,
        showDivider = showDivider,
        leading = { Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(22.dp)) },
        trailing = {
            if (status != null) {
                Text(status, style = MaterialTheme.typography.bodySmall, color = Gryonix.colors.warning)
            } else if (checked != null) {
                IOSSwitch(checked = checked, onCheckedChange = onToggle, enabled = enabled,
                    onColor = Gryonix.colors.success)
            }
            RefreshButton(contentDescription = refreshDescription, onClick = onRefresh, busy = refreshing)
            DisclosureChevron()
        },
    ) { RowLabel(title, subtitle) }
}
