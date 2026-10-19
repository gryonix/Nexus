package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
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
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import java.util.UUID

@Composable
fun AddHostScreen(
    fleet: FleetRepository,
    store: SecretStore,
    /** Asking a machine that already runs `gryonixnexusd` what it is */
    adopt: AdoptViewModel,
    onAdded: (String) -> Unit
) {
    val provisionalID = rememberSaveable { UUID.randomUUID().toString().uppercase() }
    var name by rememberSaveable { mutableStateOf("") }
    var host by rememberSaveable { mutableStateOf("") }
    var port by rememberSaveable { mutableStateOf("22") }
    var user by rememberSaveable { mutableStateOf("root") }
    var password by rememberSaveable { mutableStateOf("") }
    val adoption by adopt.state.collectAsState()
    val provisional = remember(host, port, user, name) {
        Deployment(
            id = provisionalID,
            name = name.trim().ifEmpty { host.trim() },
            topology = Topology.SINGLE_HOST,
            entry = HostEndpoint(
                host = host.trim(),
                port = port.toIntOrNull() ?: 22,
                user = user.trim(),
            ),
            usesPasswordAuth = password.isNotEmpty(),
            usesAgent = true,
        )
    }
    DisposableEffect(Unit) { onDispose { adopt.reset() } }

    val complete = remember(name, host, user, port) {
        name.isNotBlank() && host.isNotBlank() && user.isNotBlank() &&
            port.toIntOrNull()?.let { it in 1..65535 } == true
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Gryonix.colors.groupedBackground)
            .verticalScroll(rememberScrollState())
            .padding(GroupedContentPadding),
        verticalArrangement = GroupedSpacing,
    ) {
        GroupedSection {
            FieldRow(
                label = stringResource(R.string.name_label),
                value = name,
                onValueChange = { name = it },
            )
            FieldRow(
                label = stringResource(R.string.host_label),
                value = host,
                onValueChange = { host = it },
            )
            FieldRow(
                label = stringResource(R.string.port_label),
                value = port,
                onValueChange = { port = it.filter(Char::isDigit) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            )
            FieldRow(
                label = stringResource(R.string.user_label),
                value = user,
                onValueChange = { user = it },
            )
            FieldRow(
                label = stringResource(R.string.password_label),
                value = password,
                onValueChange = { password = it },
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                showDivider = false,
            )
        }

        Column(
            Modifier.padding(horizontal = Metrics.listInset),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            ProminentButton(
                text = stringResource(R.string.add_via_agent),
                onClick = {
                    if (password.isNotEmpty()) {
                        DeploymentSecrets(store, provisionalID)
                            .setPassword(password, SSHHostID.VPS)
                    }
                    adopt.start(provisional)
                },
                enabled = complete && !adoption.isRunning,
            )
            PlainButton(
                text = stringResource(R.string.save),
                onClick = {
                    val id = provisionalID
                    val deployment = Deployment(
                        id = id,
                        name = name.trim(),
                        topology = Topology.SINGLE_HOST,
                        entry = HostEndpoint(
                            host = host.trim(),
                            port = port.toIntOrNull() ?: 22,
                            user = user.trim()
                        ),
                        usesPasswordAuth = true
                    )
                    if (password.isNotEmpty()) {
                        DeploymentSecrets(store, id).setPassword(password, SSHHostID.VPS)
                    }
                    fleet.add(deployment)
                    onAdded(id)
                },
                enabled = complete,
                modifier = Modifier.align(Alignment.CenterHorizontally),
            )
        }

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

        adoption.result?.let { result ->
            GroupedSection(
                header = stringResource(R.string.adopt_found, result.services.size),
                footer = listOfNotNull(
                    stringResource(R.string.adopt_not_ours_hint)
                        .takeIf { result.installedOutside.isNotEmpty() },
                    result.notes.takeIf { it.isNotEmpty() }?.joinToString("\n"),
                ).joinToString("\n\n").takeIf { it.isNotEmpty() },
            ) {
                result.services.forEach { id ->
                    GroupedRow(showDivider = id != result.services.last()) {
                        Text(
                            id.rawValue,
                            style = MaterialTheme.typography.bodyLarge,
                            color = Gryonix.colors.label,
                        )
                    }
                }
            }
            ProminentButton(
                text = stringResource(R.string.adopt_save),
                onClick = {
                    fleet.add(
                        provisional.copy(
                            name = AgentAdoption.name(result.hostname, provisional.name),
                            domain = AgentAdoption.domain(result.domains),
                            services = result.services,
                        ),
                    )
                    onAdded(provisionalID)
                },
                modifier = Modifier.padding(horizontal = Metrics.listInset),
            )
        }
    }
}
