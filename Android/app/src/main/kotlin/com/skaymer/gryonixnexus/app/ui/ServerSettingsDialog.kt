package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.servers.ConnectionEdit
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.app.servers.ProxyStore
import com.skaymer.gryonixnexus.app.servers.ServerAccessStore
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import androidx.compose.runtime.collectAsState
import com.skaymer.gryonixnexus.servercontrol.Deployment

@Composable
fun ServerSettingsDialog(
    deployment: Deployment,
    fleet: FleetRepository,
    secrets: SecretStore,
    /** Where the Advanced half is stored — see [ServerAccessStore] */
    settings: SettingsStore,
    onDismiss: () -> Unit,
) {
    val machines = remember(deployment) { ConnectionEdit.editable(deployment) }
    val store = remember(deployment.id) { DeploymentSecrets(secrets, deployment.id) }
    val fleetDeployments by fleet.deployments.collectAsState()
    var drafts by remember(deployment.id) {
        mutableStateOf(machines.associate { it.id to ConnectionEdit.draft(it) })
    }
    var passwords by remember(deployment.id) {
        mutableStateOf(machines.associate { it.id to (store.password(it.sshHost) ?: "") })
    }
    var byPassword by remember(deployment.id) { mutableStateOf(deployment.usesPasswordAuth) }
    var access by remember(deployment.id) {
        mutableStateOf(ServerAccessStore.options(settings, deployment.id))
    }
    var lanAddress by remember(deployment.id) { mutableStateOf(store.homeAddress().orEmpty()) }
    var homePath by remember(deployment.id) { mutableStateOf(store.homePath()) }
    var advancedOpen by remember(deployment.id) { mutableStateOf(false) }
    var page by remember(deployment.id) { mutableStateOf<String?>(null) }
    var forgotten by remember(deployment.id) { mutableStateOf(emptySet<String>()) }

    IOSSheet(
        title = stringResource(R.string.server_settings),
        onClose = onDismiss,
        closeLabel = stringResource(R.string.group_cancel),
        action = SheetAction(
            title = stringResource(R.string.save),
            onSelect = {
                var updated = deployment.copy(usesPasswordAuth = byPassword)
                for (node in machines) {
                    val draft = drafts[node.id] ?: continue
                    ConnectionEdit.applying(draft, node, updated)?.let { updated = it }
                    passwords[node.id]?.takeIf { it.isNotEmpty() }
                        ?.let { store.setPassword(it, node.sshHost) }
                    if (node.id in forgotten) store.forgetHostKeyPin(node)
                }
                ServerAccessStore.save(
                    settings, deployment.id,
                    access.copy(sftpDirectory = access.sftpDirectory?.trim()?.ifEmpty { null }),
                )
                if (deployment.hasHomeHost) {
                    store.setHomeAddress(lanAddress)
                    store.setHomePath(homePath)
                }
                fleet.update(updated)
                onDismiss()
            },
        ),
    ) {
        machines.forEach { node ->
            val draft = drafts[node.id] ?: return@forEach
            GroupedSection(
                header = if (machines.size > 1) {
                    node.name.ifEmpty { node.endpoint.host }
                } else {
                    null
                },
            ) {
                FieldRow(
                    label = stringResource(R.string.host_label),
                    value = draft.host,
                    onValueChange = { drafts = drafts + (node.id to draft.copy(host = it)) },
                )
                FieldRow(
                    label = stringResource(R.string.port_label),
                    value = draft.port,
                    onValueChange = {
                        drafts = drafts + (node.id to draft.copy(port = it.filter(Char::isDigit)))
                    },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
                FieldRow(
                    label = stringResource(R.string.user_label),
                    value = draft.user,
                    onValueChange = { drafts = drafts + (node.id to draft.copy(user = it)) },
                )
                FieldRow(
                    label = stringResource(R.string.password_label),
                    value = passwords[node.id].orEmpty(),
                    onValueChange = { passwords = passwords + (node.id to it) },
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                )
                ActionRow(
                    text = stringResource(
                        if (node.id in forgotten) {
                            R.string.forget_host_key_done
                        } else {
                            R.string.forget_host_key
                        },
                    ),
                    onClick = { forgotten = forgotten + node.id },
                    danger = node.id !in forgotten,
                    enabled = node.id !in forgotten,
                    showDivider = false,
                )
            }
        }
        GroupedSection(footer = stringResource(R.string.server_settings_footer)) {
            ToggleRow(
                title = stringResource(R.string.sign_in_with_password),
                checked = byPassword,
                onCheckedChange = { byPassword = it },
                showDivider = false,
            )
        }

        if (deployment.hasHomeHost) {
            GroupedSection(note = stringResource(R.string.add_server_lan_note)) {
                FieldRow(
                    label = stringResource(R.string.add_server_lan_address),
                    value = lanAddress,
                    placeholder = "192.168.1.50",
                    onValueChange = { lanAddress = it },
                )
                HomePathRow(homePath, showDivider = false) { homePath = it }
            }
        }

        val revision by settings.revision.collectAsState()
        GroupedSection(
            header = stringResource(R.string.settings_connection_header),
            note = stringResource(R.string.settings_connection_note),
        ) { ConnectionWaitRows(settings, revision) }

        GroupedSection(footer = stringResource(R.string.server_advanced_footer)) {
            GroupedRow(
                onClick = { advancedOpen = !advancedOpen },
                showDivider = advancedOpen,
                trailing = { DisclosureChevron() },
            ) { RowLabel(stringResource(R.string.server_advanced)) }
            if (advancedOpen) {
                ToggleRow(
                    title = stringResource(R.string.server_agent_forwarding),
                    checked = access.agentForwarding,
                    enabled = false,
                    onCheckedChange = { access = access.copy(agentForwarding = it) },
                )
                GroupedRow {
                    androidx.compose.material3.Text(
                        stringResource(R.string.server_agent_forwarding_unavailable),
                        style = androidx.compose.material3.MaterialTheme.typography.bodySmall,
                        color = com.skaymer.gryonixnexus.app.ui.design.Gryonix.colors.secondaryLabel,
                    )
                }
                FieldRow(
                    label = stringResource(R.string.server_sftp_folder),
                    value = access.sftpDirectory.orEmpty(),
                    placeholder = "/",
                    onValueChange = {
                        access = access.copy(sftpDirectory = it.ifEmpty { null })
                    },
                )
                ValueRow(
                    title = stringResource(R.string.server_bastion),
                    value = bastionSummary(access.bastion, fleetDeployments),
                    onClick = { page = PAGE_BASTION },
                )
                ValueRow(
                    title = stringResource(R.string.server_fallback),
                    value = fallbackSummary(access.fallback),
                    onClick = { page = PAGE_FALLBACK },
                )
                ValueRow(
                    title = stringResource(R.string.proxy),
                    value = ProxyStore.profile(settings, access.proxyID)?.displayName
                        ?: stringResource(R.string.server_bastion_none),
                    onClick = { page = PAGE_PROXY },
                    showDivider = false,
                )
            }
        }
    }

    when (page) {
        PAGE_BASTION -> BastionPickerSheet(
            selection = access.bastion,
            fleet = fleetDeployments.filter { it.id != deployment.id },
            onSelect = { access = access.copy(bastion = it); page = null },
            onDismiss = { page = null },
        )
        PAGE_PROXY -> ProxyPickerSheet(
            selected = access.proxyID,
            store = settings,
            onSelect = { access = access.copy(proxyID = it); page = null },
            onClose = { page = null },
        )
        PAGE_FALLBACK -> FallbackAddressSheet(
            fallback = access.fallback,
            fleet = fleetDeployments.filter { it.id != deployment.id },
            primary = deployment.entry,
            onApply = { access = access.copy(fallback = it); page = null },
            onDismiss = { page = null },
        )
    }
}

private const val PAGE_BASTION = "bastion"
private const val PAGE_FALLBACK = "fallback"
private const val PAGE_PROXY = "proxy"
