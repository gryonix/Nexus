package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.outlined.Dns
import kotlinx.coroutines.launch
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.FolderShared
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.PersonAddAlt
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.terminal.ShellUserViewModel
import com.skaymer.gryonixnexus.app.terminal.TerminalProfile
import com.skaymer.gryonixnexus.app.terminal.TerminalSessions
import com.skaymer.gryonixnexus.app.terminal.TerminalViewModel
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.InfoNoteButton
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HomePathChoice
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

/** A server's saved logins, account creation and its files */
@Composable
fun ServerTerminalTab(
    deployment: Deployment,
    sessions: TerminalSessions,
    shellUsers: ShellUserViewModel?,
    onFiles: (DeploymentNode) -> Unit,
) {
    val store = remember(deployment.id) { sessions.profiles(deployment) }
    var profiles by remember(deployment.id) { mutableStateOf(store.load()) }
    val saved = remember { sessions.savedSessions() }
    var editing by remember(deployment.id) { mutableStateOf<TerminalProfile?>(null) }
    var adding by remember(deployment.id) { mutableStateOf(false) }
    var creatingAccount by remember(deployment.id) { mutableStateOf(false) }
    fun save(next: List<TerminalProfile>) {
        profiles = next
        store.save(next)
    }

    var chosenAt by remember(deployment.id) { mutableStateOf(0) }
    val machines = remember(deployment, chosenAt) { sessions.machineLogins(deployment) }
    val tabs = rememberShellTabs(deployment, sessions, saved) { machines + profiles }
    val openShells by sessions.shells.open.collectAsState()
    val mine = openShells.filter { it.deploymentID == deployment.id }
    val shown = mine.firstOrNull { it.profileID == tabs.shownID }
    if (shown != null && !tabs.listing) {
        val profile = (machines + profiles).firstOrNull { it.id == shown.profileID }
        Column(Modifier.fillMaxSize()) {
            TerminalTabStrip(mine, shown.profileID, onSelect = tabs::select, onClose = tabs::close, onNew = tabs::showList)
            if (profile != null) {
                TerminalShellView(deployment, sessions, nodeOf(deployment, profile), shown.terminal,
                    sessions.login(deployment, profile), Modifier.weight(1f))
            }
        }
        return
    }
    fun show(profile: TerminalProfile) = tabs.open(profile)

    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        if (mine.isNotEmpty()) item { OpenShellsSection(mine, onSelect = tabs::select) }
        if (machines.isNotEmpty()) {
            item {
                MachinesSection(deployment, sessions, machines, onChosen = { chosenAt++ }) { show(it) }
            }
        }
        item {
            LoginsSection(
                deployment,
                profiles,
                onOpen = { show(it) },
                onEdit = { editing = it },
                onDelete = { gone ->
                    tabs.close(gone.id)
                    save(profiles.filter { it.id != gone.id })
                },
                onAdd = { adding = true },
            )
        }
        if (shellUsers != null) item { CreateAccountRow { creatingAccount = true } }
        item { FilesSection(deployment, onFiles) }
    }

    if (adding || editing != null) {
        TerminalLoginSheet(deployment, sessions, editing, onClose = { adding = false; editing = null }) { profile ->
            save(if (profiles.any { it.id == profile.id }) profiles.map { if (it.id == profile.id) profile else it } else profiles + profile)
            adding = false
            editing = null
        }
    }
    if (creatingAccount && shellUsers != null) {
        CreateShellUserSheet(deployment = deployment, model = shellUsers, onClose = { creatingAccount = false })
    }
}

internal fun nodeOf(deployment: Deployment, profile: TerminalProfile): DeploymentNode =
    deployment.nodes.firstOrNull { it.id.toString() == profile.nodeID } ?: deployment.nodes.first()

/** Each machine, opened with the app's own login */
@Composable
private fun MachinesSection(
    deployment: Deployment,
    sessions: TerminalSessions,
    machines: List<TerminalProfile>,
    onChosen: () -> Unit,
    onOpen: (TerminalProfile) -> Unit,
) {
    val accounts = (androidx.compose.ui.platform.LocalContext.current.applicationContext as? com.skaymer.gryonixnexus.app.GryonixApplication)?.machineAccounts
    val known = remember(deployment.id) { mutableStateMapOf<String, List<com.skaymer.gryonixnexus.servercontrol.SshUserAccess>>() }
    var preparing by remember(deployment.id) { mutableStateOf<String?>(null) }
    var failure by remember(deployment.id) { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(deployment.id) {
        if (accounts == null) return@LaunchedEffect
        deployment.nodes.filter { accounts.lists(deployment, it) }.forEach { node ->
            runCatching { accounts.list(deployment, node) }.getOrNull()?.let { known[node.id.toString()] = it }
        }
    }
    GroupedSection(
        header = stringResource(R.string.terminal_machines),
        note = stringResource(R.string.terminal_machines_note),
        footer = failure,
    ) {
        machines.forEach { profile ->
            val node = nodeOf(deployment, profile)
            MachineRow(
                deployment, profile, node,
                path = sessions.pathInUse(deployment, node),
                showDivider = profile != machines.last(),
                busy = preparing == node.id.toString(),
                accounts = if (accounts != null && accounts.lists(deployment, node)) known[node.id.toString()].orEmpty() else null,
                onChoose = { user ->
                    sessions.choose(deployment, node, user)
                    onChosen()
                },
            ) {
                if (accounts == null || !accounts.lists(deployment, node)) return@MachineRow onOpen(profile)
                scope.launch {
                    preparing = node.id.toString()
                    try {
                        known[node.id.toString()] = accounts.prepare(deployment, node, profile.username, known[node.id.toString()].orEmpty())
                        failure = null
                        onOpen(profile)
                    } catch (cancelled: kotlinx.coroutines.CancellationException) {
                        throw cancelled
                    } catch (error: Exception) {
                        failure = OperationNotices.text(R.string.terminal_key_not_added, profile.username, error.message.orEmpty())
                    } finally {
                        preparing = null
                    }
                }
            }
        }
    }
}

@Composable
private fun MachineRow(
    deployment: Deployment,
    profile: TerminalProfile,
    node: DeploymentNode,
    path: HomePathChoice,
    showDivider: Boolean,
    busy: Boolean,
    accounts: List<com.skaymer.gryonixnexus.servercontrol.SshUserAccess>?,
    onChoose: (String) -> Unit,
    onOpen: () -> Unit,
) {
    val address = "${profile.username}@${node.endpoint.host}"
    GroupedRow(
        onClick = onOpen,
        showDivider = showDivider,
        leading = {
            Icon(
                if (node.routedThrough == null) Icons.Outlined.Dns else Icons.Outlined.Home,
                contentDescription = null,
                modifier = Modifier.size(22.dp),
                tint = Gryonix.colors.accent,
            )
        },
        trailing = {
            if (busy) androidx.compose.material3.CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            if (accounts != null) AccountMenu(node, profile.username, accounts, onChoose)
        },
    ) {
        RowLabel(
            machineName(deployment, node),
            when {
                node.routedThrough == null -> address
                path == HomePathChoice.LOCAL_NETWORK -> stringResource(R.string.terminal_over_local_network, address)
                else -> stringResource(R.string.terminal_through_vps, address)
            },
        )
    }
}

/** Picks the account a machine's terminal signs in as */
@Composable
private fun AccountMenu(
    node: DeploymentNode,
    chosen: String,
    accounts: List<com.skaymer.gryonixnexus.servercontrol.SshUserAccess>,
    onChoose: (String) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    val own = node.endpoint.user
    val names = listOf(own) + accounts.map { it.name }.filter { it != own }
    Box {
        IconButton(onClick = { open = true }) {
            Icon(Icons.Outlined.AccountCircle, contentDescription = stringResource(R.string.terminal_account_choice), tint = Gryonix.colors.accent)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            names.forEach { name ->
                val hasKey = name == own || accounts.firstOrNull { it.name == name }?.appKeyPresent == true
                val title = when {
                    name == own -> stringResource(R.string.terminal_account_apps, name)
                    hasKey -> name
                    else -> stringResource(R.string.terminal_account_key_added, name)
                }
                DropdownMenuItem(
                    text = { Text(if (name == chosen) "✓ $title" else title) },
                    onClick = { open = false; onChoose(name) },
                )
            }
        }
    }
}

@Composable
internal fun machineName(deployment: Deployment, node: DeploymentNode): String = when {
    node.name.isNotEmpty() -> node.name
    deployment.nodes.size == 1 -> deployment.name
    node.sshHost == SSHHostID.HOME -> stringResource(R.string.terminal_machine_local)
    node.sshHost == SSHHostID.VPS -> stringResource(R.string.terminal_machine_vps)
    else -> node.endpoint.host
}

@Composable
private fun LoginsSection(
    deployment: Deployment,
    profiles: List<TerminalProfile>,
    onOpen: (TerminalProfile) -> Unit,
    onEdit: (TerminalProfile) -> Unit,
    onDelete: (TerminalProfile) -> Unit,
    onAdd: () -> Unit,
) {
    GroupedSection(
        header = stringResource(R.string.terminal_logins),
        note = stringResource(R.string.terminal_logins_note),
    ) {
        if (profiles.isEmpty()) {
            GroupedRow { RowLabel(stringResource(R.string.terminal_no_logins), stringResource(R.string.terminal_no_logins_hint)) }
        }
        profiles.forEach { profile ->
            val machine = if (deployment.nodes.size > 1) machineName(deployment, nodeOf(deployment, profile)) else null
            LoginRow(profile, machine, { onOpen(profile) }, { onEdit(profile) }, { onDelete(profile) })
        }
        GroupedRow(
            onClick = onAdd,
            showDivider = false,
            leading = { Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(22.dp)) },
        ) {
            Text(stringResource(R.string.terminal_add_login), style = MaterialTheme.typography.bodyLarge, color = Gryonix.colors.accent)
        }
    }
}

@Composable
private fun LoginRow(profile: TerminalProfile, machine: String?, onOpen: () -> Unit, onEdit: () -> Unit, onDelete: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    GroupedRow(
        onClick = onOpen,
        leading = {
            Box(
                Modifier.size(28.dp).clip(RoundedCornerShape(7.dp)).background(Gryonix.colors.accent.copy(alpha = 0.12f)),
            ) {
                Icon(Icons.Outlined.Terminal, contentDescription = null, modifier = Modifier.size(18.dp).padding(0.dp).align(androidx.compose.ui.Alignment.Center))
            }
        },
        trailing = {
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreHoriz, contentDescription = null) }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.terminal_login_edit)) }, onClick = { menu = false; onEdit() })
                    DropdownMenuItem(
                        text = { Text(stringResource(R.string.terminal_login_delete), color = Gryonix.colors.danger) },
                        onClick = { menu = false; onDelete() },
                    )
                }
            }
        },
    ) {
        val kind = stringResource(if (profile.usesAppKey) R.string.terminal_kind_app_key else R.string.terminal_kind_password)
        RowLabel(profile.username, if (machine == null) kind else "$kind · $machine")
    }
}

@Composable
private fun CreateAccountRow(onOpen: () -> Unit) {
    GroupedSection {
        GroupedRow(
            onClick = onOpen,
            showDivider = false,
            leading = { Icon(Icons.Outlined.PersonAddAlt, contentDescription = null, modifier = Modifier.size(22.dp)) },
            trailing = {
                com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron()
                InfoNoteButton(
                    title = stringResource(R.string.terminal_create_account),
                    note = stringResource(R.string.terminal_create_account_note),
                )
            },
        ) { RowLabel(stringResource(R.string.terminal_create_server_account)) }
    }
}

@Composable
private fun FilesSection(deployment: Deployment, onFiles: (DeploymentNode) -> Unit) {
    GroupedSection(header = stringResource(R.string.terminal_files)) {
        deployment.nodes.forEach { node ->
            val home = node.sshHost == SSHHostID.HOME
            NavRow(
                if (home) Icons.Outlined.FolderShared else Icons.Outlined.Folder,
                filesTitle(deployment, node),
                { onFiles(node) },
                showDivider = node != deployment.nodes.last(),
            )
        }
    }
}

@Composable
private fun filesTitle(deployment: Deployment, node: DeploymentNode): String = when {
    node.name.isNotEmpty() -> stringResource(R.string.terminal_node_files, node.name)
    node.sshHost == SSHHostID.HOME -> stringResource(R.string.terminal_local_files)
    deployment.nodes.size > 1 -> stringResource(R.string.terminal_vps_files)
    else -> stringResource(R.string.terminal_server_files)
}

/** Adds or edits one saved login */
@Composable
private fun TerminalLoginSheet(
    deployment: Deployment,
    sessions: TerminalSessions,
    editing: TerminalProfile?,
    onClose: () -> Unit,
    onSave: (TerminalProfile) -> Unit,
) {
    var node by remember { mutableStateOf(editing?.let { nodeOf(deployment, it) } ?: deployment.nodes.first()) }
    var username by remember { mutableStateOf(editing?.username ?: TerminalViewModel.defaultUsername(node)) }
    var useAppKey by remember { mutableStateOf(editing?.usesAppKey ?: sessions.hasAppKey(deployment)) }
    var password by remember { mutableStateOf(editing?.password.orEmpty()) }
    var keepAlive by remember { mutableStateOf(editing?.keepAliveWithTmux ?: false) }
    val ready = username.isNotBlank() && (useAppKey || password.isNotEmpty())
    IOSSheet(
        title = stringResource(if (editing == null) R.string.terminal_add_login else R.string.terminal_login_edit),
        onClose = onClose,
        closeLabel = stringResource(R.string.access_cancel),
        action = SheetAction(stringResource(R.string.containers_done), enabled = ready) {
            onSave(
                (editing ?: TerminalProfile(username = "", usesAppKey = useAppKey)).copy(
                    username = username.trim(),
                    nodeID = node.id.toString(),
                    usesAppKey = useAppKey,
                    password = if (useAppKey) "" else password,
                    keepAliveWithTmux = keepAlive,
                )
            )
        },
    ) {
        if (deployment.isMultiHost) {
            GroupedSection(header = stringResource(R.string.terminal_pick_machine)) {
                deployment.nodes.forEach { candidate ->
                    CheckRow(
                        title = candidate.name.ifEmpty { candidate.endpoint.host },
                        subtitle = "${candidate.endpoint.user}@${candidate.endpoint.host}",
                        checked = candidate.id == node.id,
                        onClick = { node = candidate },
                        showDivider = candidate != deployment.nodes.last(),
                    )
                }
            }
        }
        GroupedSection(footer = if (!useAppKey) stringResource(R.string.terminal_password_note) else null) {
            FieldRow(
                label = stringResource(R.string.terminal_account),
                value = username,
                onValueChange = { username = it },
                showDivider = sessions.hasAppKey(deployment) || !useAppKey,
            )
            if (sessions.hasAppKey(deployment)) {
                ToggleRow(
                    title = stringResource(R.string.terminal_use_app_key),
                    checked = useAppKey,
                    onCheckedChange = { useAppKey = it },
                    showDivider = !useAppKey,
                )
            }
            if (!useAppKey) {
                FieldRow(
                    label = stringResource(R.string.terminal_password),
                    value = password,
                    onValueChange = { password = it },
                    visualTransformation = PasswordVisualTransformation(),
                    showDivider = false,
                )
            }
        }
        GroupedSection(footer = stringResource(R.string.terminal_tmux_note)) {
            ToggleRow(
                title = stringResource(R.string.terminal_tmux_title),
                checked = keepAlive,
                onCheckedChange = { keepAlive = it },
                showDivider = false,
            )
        }
    }
}
