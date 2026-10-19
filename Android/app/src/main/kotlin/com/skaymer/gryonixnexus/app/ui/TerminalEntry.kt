package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import com.skaymer.gryonixnexus.app.terminal.TerminalDirectHost
import com.skaymer.gryonixnexus.app.terminal.TerminalDirectHostStore
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.AlertFields
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.InfoNoteButton
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.ProminentButton
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.terminal.ShellUserViewModel
import com.skaymer.gryonixnexus.app.terminal.TerminalSessions
import com.skaymer.gryonixnexus.app.terminal.TerminalViewModel
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.transport.TerminalLogin

@Composable
fun TerminalSection(
    deployment: Deployment,
    sessions: TerminalSessions,
    modifier: Modifier = Modifier,
    /** Making an account to open a shell WITH — see [CreateShellUserSheet] */
    shellUsers: ShellUserViewModel? = null,
) {
    val scope = rememberCoroutineScope()
    var creatingAccount by remember(deployment.id) { mutableStateOf(false) }
    var node by remember(deployment.id) { mutableStateOf(deployment.nodes.first()) }
    var username by remember(deployment.id) {
        mutableStateOf(TerminalViewModel.defaultUsername(deployment.nodes.first()))
    }
    var password by remember(deployment.id) { mutableStateOf("") }
    var useAppKey by remember(deployment.id) { mutableStateOf(sessions.hasAppKey(deployment)) }
    var opened by remember(deployment.id) { mutableStateOf(false) }

    if (opened) {
        val terminal = remember(deployment.id, node.id) {
            TerminalViewModel(
                scope = scope,
                sessions = { endpoint, login ->
                    sessions.transport(endpoint, login) { host, key -> sessions.pin(deployment, host, key) }
                },
            )
        }
        TerminalScreen(
            terminal = terminal,
            onOpen = { columns, rows ->
                terminal.open(
                    endpoint = sessions.endpoint(deployment, node),
                    login = TerminalLogin(
                        username = username.trim(),
                        secret = if (useAppKey) {
                            TerminalLogin.Secret.PrivateKeySeed(sessions.appKeySeed(deployment))
                        } else {
                            TerminalLogin.Secret.Password(password)
                        },
                    ),
                    columns = columns,
                    rows = rows,
                )
            },
            modifier = modifier,
        )
        return
    }

    LazyColumn(
        modifier
            .fillMaxSize()
            .background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        if (deployment.isMultiHost) {
            item {
                GroupedSection(header = stringResource(R.string.terminal_pick_machine)) {
                    deployment.nodes.forEach { candidate ->
                        CheckRow(
                            title = candidate.name.ifEmpty { candidate.endpoint.host },
                            subtitle = "${candidate.endpoint.user}@${candidate.endpoint.host}",
                            checked = candidate.id == node.id,
                            onClick = {
                                node = candidate
                                username = TerminalViewModel.defaultUsername(candidate)
                            },
                            showDivider = candidate != deployment.nodes.last(),
                        )
                    }
                }
            }
        }

        item {
            GroupedSection(
                footer = if (!useAppKey) stringResource(R.string.terminal_password_note) else null,
            ) {
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
        }

        item {
            ProminentButton(
                text = stringResource(R.string.terminal_open),
                onClick = { opened = true },
                enabled = username.isNotBlank() && (useAppKey || password.isNotEmpty()),
                modifier = Modifier.padding(horizontal = Metrics.listInset),
            )
        }

        if (shellUsers != null) {
            item {
                GroupedSection {
                    ActionRow(
                        text = stringResource(R.string.terminal_create_account),
                        onClick = { creatingAccount = true },
                        showDivider = false,
                        trailing = {
                            InfoNoteButton(
                                title = stringResource(R.string.terminal_create_account),
                                note = stringResource(R.string.terminal_create_account_note),
                            )
                        },
                    )
                }
            }
        }
    }

    if (creatingAccount && shellUsers != null) {
        CreateShellUserSheet(
            deployment = deployment,
            model = shellUsers,
            onClose = { creatingAccount = false },
        )
    }
}

internal fun Deployment.firstTerminalNode(): DeploymentNode = nodes.first()

@Composable
fun TerminalTab(
    fleet: com.skaymer.gryonixnexus.app.servers.FleetRepository,
    sessions: TerminalSessions,
    /** Machines this app never set up — see `TerminalDirectHost` */
    directHosts: TerminalDirectHostStore,
    /** Making an account to open a shell with — see [CreateShellUserSheet] */
    shellUsers: ShellUserViewModel? = null,
) {
    val deployments by fleet.deployments.collectAsState()
    var saved by remember { mutableStateOf(directHosts.load()) }
    var chosen by remember { mutableStateOf<String?>(null) }
    var adding by remember { mutableStateOf(false) }

    val server = deployments.firstOrNull { it.id == chosen }
        ?: saved.firstOrNull { it.id == chosen }?.deployment

    if (server != null) {
        Column(Modifier.fillMaxSize()) {
            TerminalSection(server, sessions, Modifier.weight(1f), shellUsers = shellUsers)
            PlainButton(
                text = stringResource(R.string.terminal_close),
                onClick = { chosen = null },
                modifier = Modifier.padding(horizontal = 8.dp),
            )
        }
        return
    }

    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        if (deployments.isEmpty() && saved.isEmpty()) {
            item {
                Text(
                    stringResource(R.string.terminal_no_servers),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.secondaryLabel,
                    modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
                )
            }
        }
        if (deployments.isNotEmpty()) {
            item {
                GroupedSection {
                    deployments.forEach { deployment ->
                        ValueRow(
                            title = deployment.name,
                            subtitle = deployment.entry.host,
                            value = null,
                            onClick = { chosen = deployment.id },
                            showDivider = deployment != deployments.last(),
                        )
                    }
                }
            }
        }
        if (saved.isNotEmpty()) {
            item {
                GroupedSection(header = stringResource(R.string.terminal_other_machines)) {
                    saved.forEach { host ->
                        GroupedRow(
                            onClick = { chosen = host.id },
                            showDivider = host != saved.last(),
                            trailing = {
                                IconButton(
                                    onClick = {
                                        directHosts.remove(host.id)
                                        saved = directHosts.load()
                                    },
                                    modifier = Modifier.size(28.dp),
                                ) {
                                    Icon(
                                        Icons.Filled.Close,
                                        contentDescription =
                                            stringResource(R.string.terminal_host_remove),
                                        tint = Gryonix.colors.danger,
                                        modifier = Modifier.size(18.dp),
                                    )
                                }
                            },
                        ) {
                            RowLabel(host.title, "${host.username}@${host.host}:${host.port}")
                        }
                    }
                }
            }
        }
        item {
            GroupedSection {
                ActionRow(
                    text = stringResource(R.string.terminal_add_host),
                    onClick = { adding = true },
                    showDivider = false,
                )
            }
        }
    }

    if (adding) {
        TerminalHostDialog(
            onCancel = { adding = false },
            onSave = { host ->
                directHosts.upsert(host)
                saved = directHosts.load()
                adding = false
            },
        )
    }
}

@Composable
private fun TerminalHostDialog(
    onCancel: () -> Unit,
    onSave: (TerminalDirectHost) -> Unit,
) {
    var name by remember { mutableStateOf("") }
    var host by remember { mutableStateOf("") }
    var port by remember { mutableStateOf("22") }
    var user by remember { mutableStateOf("root") }

    IOSAlert(
        title = stringResource(R.string.terminal_add_host),
        onDismiss = onCancel,
        actions = listOf(
            AlertAction(stringResource(R.string.access_cancel), onSelect = onCancel),
            AlertAction(
                stringResource(R.string.containers_done),
                preferred = true,
                enabled = host.isNotBlank() && user.isNotBlank(),
                onSelect = {
                    onSave(
                        TerminalDirectHost(
                            name = name,
                            host = host.trim(),
                            port = port.toIntOrNull()?.takeIf { it in 1..65535 } ?: 22,
                            username = user.trim(),
                        )
                    )
                },
            ),
        ),
    ) {
        AlertFields {
            FieldRow(
                label = stringResource(R.string.terminal_host_address),
                value = host,
                onValueChange = { host = it },
            )
            FieldRow(
                label = stringResource(R.string.terminal_host_user),
                value = user,
                onValueChange = { user = it },
            )
            FieldRow(
                label = stringResource(R.string.terminal_host_port),
                value = port,
                onValueChange = { port = it.filter { c -> c.isDigit() } },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            )
            FieldRow(
                label = stringResource(R.string.terminal_host_name),
                value = name,
                onValueChange = { name = it },
                showDivider = false,
            )
        }
    }
}
