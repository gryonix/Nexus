package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import com.skaymer.gryonixnexus.app.ui.design.Separator
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.background
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.ProminentButton
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import com.skaymer.gryonixnexus.app.servers.AdoptViewModel
import com.skaymer.gryonixnexus.app.servers.AgentAdoption
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.catalog.Topology
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import com.skaymer.gryonixnexus.app.configurator.ScenarioOption
import com.skaymer.gryonixnexus.app.secrets.AppIdentities
import com.skaymer.gryonixnexus.app.servers.AdoptState
import com.skaymer.gryonixnexus.app.servers.ProbeState
import com.skaymer.gryonixnexus.app.servers.ServerTint
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.AlertFields
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.MenuCheckItem
import com.skaymer.gryonixnexus.app.ui.design.MenuValueRow
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.servercontrol.AccessGrantCommand
import com.skaymer.gryonixnexus.servercontrol.MetricsIndicatorStyle
import com.skaymer.gryonixnexus.servercontrol.ServerGroups
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun AddHostScreen(
    form: AddHostForm,
    fleet: FleetRepository,
    store: SecretStore,
    /** Asking a machine that already runs `gryonixnexusd` what it is */
    adopt: AdoptViewModel,
    onAdded: (String) -> Unit
) {
    val adoption by adopt.state.collectAsState()
    val probe by adopt.probe.collectAsState()
    val deployments by fleet.deployments.collectAsState()
    DisposableEffect(Unit) { onDispose { adopt.reset() } }
    LaunchedEffect(adoption.result) { adoption.result?.let { form.adopted(it); form.step = AddHostForm.Step.DETAILS } }
    LaunchedEffect(probe) { if (probe == ProbeState.Ok) form.nameFromHost() }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Gryonix.colors.groupedBackground)
            .verticalScroll(rememberScrollState())
            .padding(GroupedContentPadding),
        verticalArrangement = GroupedSpacing,
    ) {
        if (form.step == AddHostForm.Step.CONNECTION) {
            ConnectionStep(form, probe, store, adoption.isRunning, onChange = adopt::forgetProbe) {
                form.stage(store)
                adopt.start(form.deployment())
            }
            AdoptionProgress(adoption)
        } else {
            DetailsStep(form, ServerGroups.known(deployments))
        }
        AddHostActions(form, probe, onProbe = {
            form.stage(store)
            adopt.probe(form.deployment())
        }) {
            form.stage(store)
            fleet.add(form.deployment())
            onAdded(form.id)
        }
    }
}

/** The bottom buttons: connect, then next, then save */
@Composable
private fun AddHostActions(form: AddHostForm, probe: ProbeState, onProbe: () -> Unit, onSave: () -> Unit) {
    Column(Modifier.padding(horizontal = Metrics.listInset), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        when (form.step) {
            AddHostForm.Step.CONNECTION -> ProminentButton(
                text = stringResource(if (probe == ProbeState.Ok) R.string.quick_transfer_next else R.string.add_server_connect),
                onClick = { if (probe == ProbeState.Ok) form.step = AddHostForm.Step.DETAILS else onProbe() },
                enabled = form.canConnect && probe != ProbeState.Checking,
            )
            AddHostForm.Step.DETAILS -> {
                ProminentButton(text = stringResource(R.string.save), onClick = onSave, enabled = form.canSave)
                PlainButton(
                    text = stringResource(R.string.back),
                    onClick = { form.step = AddHostForm.Step.CONNECTION },
                    modifier = Modifier.align(Alignment.CenterHorizontally),
                )
            }
        }
    }
}

/** The adoption's progress or its failure */
@Composable
private fun AdoptionProgress(adoption: AdoptState) {
        adoption.stage?.let { stage ->
        Row(
            Modifier.padding(horizontal = Metrics.listInset + 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CircularProgressIndicator(
                Modifier.size(18.dp),
                strokeWidth = 2.dp,
                color = Gryonix.colors.tertiaryLabel,
            )
            Text(
                stringResource(
                    when (stage) {
                        AgentAdoption.Stage.CONNECTING -> R.string.adopt_connecting
                        AgentAdoption.Stage.PAIRING -> R.string.adopt_pairing
                        AgentAdoption.Stage.DISCOVERING -> R.string.adopt_discovering
                    },
                ),
                style = MaterialTheme.typography.bodyMedium,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(start = 10.dp),
            )
        }
    }

        adoption.failure?.let { failure ->
        GroupedSection(footer = failure.detail) {
            GroupedRow(showDivider = false) {
                Text(
                    stringResource(
                        when (failure) {
                            is AgentAdoption.Failure.KeyRefused -> R.string.adopt_key_refused
                            is AgentAdoption.Failure.Unreachable -> R.string.adopt_unreachable
                            is AgentAdoption.Failure.NoAgent -> R.string.adopt_no_agent
                            is AgentAdoption.Failure.AgentFailed -> R.string.adopt_agent_failed
                        },
                    ),
                    style = MaterialTheme.typography.bodyLarge,
                    color = Gryonix.colors.danger,
                )
            }
        }
    }
}

/** Shape, address, sign-in and the app's key */
@Composable
private fun ConnectionStep(
    form: AddHostForm,
    probe: ProbeState,
    store: SecretStore,
    adopting: Boolean,
    onChange: () -> Unit,
    onCheckAgent: () -> Unit,
) {
    val relay = form.topology == Topology.VPS_RELAY_WITH_HOME_BACKEND
    GroupedSection(
        header = stringResource(if (relay) R.string.add_server_vps_ssh_header else R.string.add_server_ssh_header),
        footer = probeFooter(probe),
    ) {
        ShapeRow(form) { onChange() }
        FieldRow(
            label = stringResource(if (relay) R.string.wizard_vps_address else R.string.wizard_server_address),
            value = form.host, onValueChange = { form.host = it; onChange() },
            placeholder = if (form.scope == DeploymentScope.LOCAL_ONLY) "192.168.1.24" else "203.0.113.4",
        )
        FieldRow(
            label = stringResource(R.string.port_label), value = form.port,
            onValueChange = { form.port = it.filter(Char::isDigit); onChange() },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        )
        FieldRow(label = stringResource(R.string.user_label), value = form.user, onValueChange = { form.user = it; onChange() })
        ToggleRow(
            title = stringResource(R.string.add_server_password_toggle), checked = form.usesPassword,
            onCheckedChange = { form.usesPassword = it; onChange() },
        )
        if (form.usesPassword) PasswordField(form.password) { form.password = it; onChange() }
        ActionRow(stringResource(R.string.add_server_check_agent), onClick = onCheckAgent,
            enabled = form.canConnect && !adopting, showDivider = false)
    }
    if (!form.usesPassword) AppKeyCard(store, form.id)
    if (relay) LocalServerCard(form, onChange)
}

@Composable
private fun PasswordField(value: String, onValue: (String) -> Unit) {
    FieldRow(
        label = stringResource(R.string.password_label), value = value, onValueChange = onValue,
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
    )
}

/** The kind of server: single, relay, local, tunnel */
@Composable
private fun ShapeRow(form: AddHostForm, onChange: () -> Unit) {
    val chosen = ScenarioOption.all.firstOrNull { it.topology == form.topology && it.scope == form.scope }
        ?: ScenarioOption.all.first()
    MenuValueRow(stringResource(R.string.add_server_shape), stringResource(chosen.title)) { close ->
        ScenarioOption.all.forEach { option ->
            MenuCheckItem(stringResource(option.title), option == chosen) {
                form.topology = option.topology
                form.scope = option.scope
                onChange()
                close()
            }
        }
    }
}

@Composable
private fun probeFooter(probe: ProbeState): String = when (probe) {
    ProbeState.Unchecked -> stringResource(R.string.access_key_hint)
    ProbeState.Checking -> stringResource(R.string.quick_transfer_connecting)
    ProbeState.Ok -> stringResource(R.string.add_server_connected)
    is ProbeState.Failed -> probe.message.ifEmpty { stringResource(R.string.add_server_unexpected) }
}

/** The app's public key and the command that installs it */
@Composable
private fun AppKeyCard(store: SecretStore, deploymentID: String) {
    val clipboard = LocalClipboardManager.current
    var key by remember(deploymentID) { mutableStateOf("") }
    var copied by remember { mutableStateOf<Int?>(null) }
    LaunchedEffect(deploymentID) {
        key = runCatching { withContext(Dispatchers.IO) { AppIdentities(store).publicKey(deploymentID) } }.getOrDefault("")
    }
    val footer = stringResource(R.string.add_server_key_footer) +
        (copied?.let { "\n" + stringResource(it) } ?: "")
    GroupedSection(header = stringResource(R.string.add_server_key_header), footer = footer) {
        if (key.isEmpty()) {
            GroupedRow { Text(stringResource(R.string.add_server_key_preparing), color = Gryonix.colors.secondaryLabel) }
        } else {
            GroupedRow {
                Text(key, style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                    color = Gryonix.colors.secondaryLabel, maxLines = 3)
            }
            ActionRow(stringResource(R.string.add_server_copy_command), onClick = {
                clipboard.setText(AnnotatedString(AccessGrantCommand.command(key)))
                copied = R.string.add_server_command_copied
            })
            ActionRow(stringResource(R.string.add_server_copy_key), showDivider = false, onClick = {
                clipboard.setText(AnnotatedString(key))
                copied = R.string.add_server_key_copied
            })
        }
    }
}

/** The machine behind the relay, reached through the tunnel */
@Composable
private fun LocalServerCard(form: AddHostForm, onChange: () -> Unit) {
    GroupedSection(header = stringResource(R.string.logins_local_server), note = stringResource(R.string.add_server_lan_note)) {
        FieldRow(label = stringResource(R.string.user_label), value = form.homeUser,
            onValueChange = { form.homeUser = it }, placeholder = form.user.ifBlank { "root" })
        FieldRow(label = stringResource(R.string.add_server_wg_address), value = form.homeWGAddress,
            onValueChange = { form.homeWGAddress = it }, placeholder = "10.8.0.2")
        FieldRow(label = stringResource(R.string.add_server_lan_address), value = form.homeLANAddress,
            onValueChange = { form.homeLANAddress = it }, placeholder = "192.168.1.50")
        HomePathRow(form.homePath) { form.homePath = it }
        FieldRow(label = stringResource(R.string.add_server_wg_interface), value = form.wgInterface,
            onValueChange = { form.wgInterface = it }, placeholder = "wg0", showDivider = form.usesPassword)
        if (form.usesPassword) PasswordField(form.homePassword) { form.homePassword = it; onChange() }
    }
}

/** Name, domain, groups, load indicator and colour */
@Composable
private fun DetailsStep(form: AddHostForm, groups: List<String>) {
    GroupedSection(header = stringResource(R.string.vpn_speed_server)) {
        FieldRow(label = stringResource(R.string.name_label), value = form.name, onValueChange = { form.name = it })
        FieldRow(label = stringResource(R.string.domain_label), value = form.domain,
            onValueChange = { form.domain = it }, placeholder = "example.com")
        GroupsRow(form, groups)
        IndicatorRow(form)
    }
    GroupedSection(header = stringResource(R.string.settings_appearance)) {
        IconRow(form)
        TintRow(form)
    }
}

@Composable
private fun IconRow(form: AddHostForm) {
    val tint = form.tint?.composeColor() ?: Gryonix.colors.accent
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(stringResource(R.string.card_icon), style = MaterialTheme.typography.bodyLarge)
        ServerIconPicker(form.icon, tint) { form.icon = it }
    }
    Separator(startInset = 16.dp)
}

@Composable
private fun GroupsRow(form: AddHostForm, known: List<String>) {
    var naming by remember { mutableStateOf(false) }
    val offered = (known + form.tags).distinctBy { it.lowercase() }
    val shown = form.tags.ifEmpty { listOf(stringResource(R.string.swap_none)) }.joinToString(", ")
    MenuValueRow(stringResource(R.string.add_server_groups), shown) { close ->
        offered.forEach { group ->
            MenuCheckItem(group, form.tags.any { it.equals(group, ignoreCase = true) }) {
                form.tags = ServerGroups.setting(form.tags.none { it.equals(group, ignoreCase = true) }, group, form.tags)
            }
        }
        DropdownMenuItem(text = { Text(stringResource(R.string.group_new)) }, onClick = { naming = true; close() })
    }
    if (naming) {
        NameEditSheet(
            title = stringResource(R.string.group_new_title),
            label = stringResource(R.string.group_name),
            initial = "",
            valid = { ServerGroups.clean(it) != null },
            onSave = { name -> ServerGroups.clean(name)?.let { form.tags = ServerGroups.setting(true, it, form.tags) } },
            onClose = { naming = false },
        )
    }
}

@Composable
private fun IndicatorRow(form: AddHostForm) {
    val label = form.indicator?.let { stringResource(it.labelRes) } ?: stringResource(R.string.add_server_app_default)
    MenuValueRow(stringResource(R.string.card_indicator), label, showDivider = false) { close ->
        MenuCheckItem(stringResource(R.string.add_server_app_default), form.indicator == null) { form.indicator = null; close() }
        MetricsIndicatorStyle.entries.forEach { style ->
            MenuCheckItem(stringResource(style.labelRes), form.indicator == style) { form.indicator = style; close() }
        }
    }
}

@Composable
private fun TintRow(form: AddHostForm) {
    val label = form.tint?.let { stringResource(it.labelRes) } ?: stringResource(R.string.tint_default)
    MenuValueRow(stringResource(R.string.card_color), label, showDivider = false) { close ->
        MenuCheckItem(stringResource(R.string.tint_default), form.tint == null) { form.tint = null; close() }
        ServerTint.entries.forEach { tint ->
            MenuCheckItem(stringResource(tint.labelRes), form.tint == tint) { form.tint = tint; close() }
        }
    }
}
