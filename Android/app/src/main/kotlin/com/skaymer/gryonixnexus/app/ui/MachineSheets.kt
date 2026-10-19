package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.AddMachineViewModel
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** Adds a machine to a server that already exists */
@Composable
fun AddMachineDialog(
    deployment: Deployment,
    machines: AddMachineViewModel,
    onCancel: () -> Unit,
    onAdded: () -> Unit,
) {
    val state by machines.state.collectAsState()
    val content = rememberScrollState()
    var address by remember { mutableStateOf("") }
    var port by remember { mutableStateOf("22") }
    var user by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var parent by remember { mutableStateOf<String?>(null) }
    var parentMenu by remember { mutableStateOf(false) }
    var password by remember { mutableStateOf("") }
    val needsPassword = AddMachineViewModel.needsPassword(deployment)

    DisposableEffect(deployment.id) { onDispose { machines.reset() } }
    LaunchedEffect(state.proved, state.errorMessage) {
        if (state.proved != null || state.errorMessage != null) {
            content.animateScrollTo(content.maxValue)
        }
    }

    val parentName = deployment.nodes.firstOrNull { it.id == parent }?.let {
        it.name.ifEmpty { it.endpoint.host }
    }

    IOSSheet(
        title = stringResource(R.string.machines_add_title),
        onClose = onCancel,
        closeLabel = stringResource(R.string.containers_cancel),
        scrollable = false,
        action = SheetAction(
            title = stringResource(R.string.machines_add),
            enabled = state.proved != null,
            onSelect = { if (machines.add(deployment)) onAdded() },
        ),
    ) {
        Column(
            Modifier.verticalScroll(content).padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(Metrics.sectionGap),
        ) {
            GroupedSection(footer = stringResource(R.string.machines_key_note)) {
                FieldRow(
                    label = stringResource(R.string.machines_address),
                    value = address,
                    onValueChange = { address = it },
                )
                FieldRow(
                    label = stringResource(R.string.machines_port),
                    value = port,
                    onValueChange = { port = it },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
                FieldRow(
                    label = stringResource(R.string.machines_user),
                    value = user,
                    onValueChange = { user = it },
                    showDivider = false,
                )
            }

            if (needsPassword) {
                GroupedSection(footer = stringResource(R.string.machines_password_note)) {
                    FieldRow(
                        label = stringResource(R.string.machines_password),
                        value = password,
                        onValueChange = { password = it },
                        visualTransformation = PasswordVisualTransformation(),
                        showDivider = false,
                    )
                }
            }

            GroupedSection {
                FieldRow(
                    label = stringResource(R.string.machines_name),
                    value = name,
                    onValueChange = { name = it },
                )
                Box {
                    ValueRow(
                        title = stringResource(R.string.machines_reached_through),
                        value = parentName ?: stringResource(R.string.machines_own_address),
                        onClick = { parentMenu = true },
                        showDivider = false,
                    )
                    DropdownMenu(
                        expanded = parentMenu,
                        onDismissRequest = { parentMenu = false },
                    ) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.machines_own_address)) },
                            onClick = { parent = null; parentMenu = false },
                        )
                        deployment.nodes.forEach { node ->
                            DropdownMenuItem(
                                text = { Text(node.name.ifEmpty { node.endpoint.host }) },
                                onClick = { parent = node.id; parentMenu = false },
                            )
                        }
                    }
                }
            }

            GroupedSection(
                footer = state.errorMessage
                    ?: stringResource(R.string.machines_only_after_answer),
            ) {
                ActionRow(
                    text = stringResource(R.string.machines_check),
                    enabled = !state.isChecking &&
                        AddMachineViewModel.canCheck(address, user, password, needsPassword),
                    onClick = {
                        machines.check(
                            deployment,
                            AddMachineViewModel.candidate(address, port, user, name, parent),
                            password,
                        )
                    },
                    showDivider = state.isChecking || state.proved != null,
                    leading = if (!state.isChecking) {
                        null
                    } else {
                        {
                            CircularProgressIndicator(
                                Modifier.size(16.dp),
                                strokeWidth = 2.dp,
                                color = Gryonix.colors.tertiaryLabel,
                            )
                        }
                    },
                )
                state.proved?.let {
                    GroupedRow(showDivider = false) {
                        Text(
                            stringResource(R.string.machines_answered),
                            style = MaterialTheme.typography.bodyMedium,
                            color = Gryonix.colors.success,
                        )
                    }
                }
            }
        }
    }
}
