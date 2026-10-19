package com.skaymer.gryonixnexus.app.ui

import kotlin.math.roundToInt
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.ui.graphics.StrokeCap
import com.skaymer.gryonixnexus.app.access.SudoProblem
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.AdvancedSection
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.ProminentButton
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.install.InstallState
import com.skaymer.gryonixnexus.app.install.InstallTarget
import com.skaymer.gryonixnexus.app.install.InstallViewModel

@Composable
fun InstallScreen(model: InstallViewModel, onOpenServer: () -> Unit) {
    val state by model.state.collectAsState()
    LazyColumn(
        modifier = Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        when (val phase = state.phase) {
            is InstallState.Phase.Setup -> setup(model, state)
            is InstallState.Phase.Installing -> running(model, state)
            is InstallState.Phase.Failed -> failure(model, state, phase.reason)
            is InstallState.Phase.Finished -> finished(state, onOpenServer)
        }
    }
}

// ------------------------------------------------------------------- Setup

private fun androidx.compose.foundation.lazy.LazyListScope.setup(
    model: InstallViewModel,
    state: InstallState,
) {
    item { Caption(stringResource(R.string.install_subtitle)) }

    if (state.needsAccessGrant) {
        item {
            SectionTitle(stringResource(R.string.install_grant_step))
            Caption(stringResource(R.string.install_grant_hint))
        }
        item { CopyableCommand(model.grantCommand) }
        model.publicKey?.let { key ->
            item {
                val copySecret = rememberSecretClipboard()
                AdvancedSection {
                    GroupedRow(
                        showDivider = false,
                        trailing = {
                            IconButton(onClick = { copySecret(key) }, modifier = Modifier.size(28.dp)) {
                                Icon(
                                    Icons.Filled.ContentCopy,
                                    contentDescription = stringResource(R.string.install_copy_key),
                                    tint = Gryonix.colors.accent,
                                    modifier = Modifier.size(18.dp),
                                )
                            }
                        },
                    ) {
                        SelectionContainer {
                            Text(
                                key,
                                style = MaterialTheme.typography.bodySmall,
                                fontFamily = FontFamily.Monospace,
                                color = Gryonix.colors.label,
                            )
                        }
                    }
                }
            }
        }
    }

    item { SectionTitle(stringResource(R.string.install_machines_step)) }
    items(state.targets.size) { index ->
        TargetCard(model, state.targets[index])
        val target = state.targets[index]
        InstallStorageSections(model, target, model.requirements(target.kind),
            isRelay = target.kind == InstallTarget.Kind.VPS)
    }

    model.dnsRecords?.let { records ->
        item { SectionTitle(stringResource(R.string.install_dns_records)) }
        item { CopyableCommand(records) }
    }

    item {
        ProminentButton(
            text = stringResource(R.string.install_start),
            onClick = { model.start() },
            enabled = state.canStart,
            modifier = Modifier.padding(horizontal = Metrics.listInset),
        )
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.bodySmall,
        color = Gryonix.colors.secondaryLabel,
        modifier = Modifier.padding(
            start = Metrics.listInset + 4.dp,
            end = Metrics.listInset + 4.dp,
            bottom = 6.dp,
        ),
    )
}

@Composable
private fun Caption(text: String, danger: Boolean = false) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = if (danger) Gryonix.colors.danger else Gryonix.colors.secondaryLabel,
        modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
    )
}

@Composable
private fun TargetCard(model: InstallViewModel, target: InstallTarget) {
    GroupedSection(
        header = stringResource(
            when (target.kind) {
                InstallTarget.Kind.SINGLE -> R.string.install_machine_single
                InstallTarget.Kind.VPS -> R.string.install_machine_vps
                InstallTarget.Kind.HOME -> R.string.install_machine_home
            }
        ),
        footer = if (target.kind == InstallTarget.Kind.HOME) {
            stringResource(R.string.install_home_hint)
        } else {
            stringResource(R.string.install_account_hint)
        },
    ) {
        OwnAddressRow(
            label = stringResource(R.string.host_label),
            value = target.address,
            onValueChange = { value -> model.edit(target.slot) { it.copy(address = value) } },
        )
        FieldRow(
            label = stringResource(R.string.port_label),
            value = target.port.toString(),
            onValueChange = { value ->
                val digits = value.filter(Char::isDigit)
                model.edit(target.slot) { it.copy(port = digits.toIntOrNull() ?: 0) }
            },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        )
        FieldRow(
            label = stringResource(R.string.install_account),
            value = target.username,
            onValueChange = { value -> model.edit(target.slot) { it.copy(username = value) } },
        )
        AuthFields(model, target)
        ActionRow(
            text = stringResource(R.string.install_check),
            onClick = { model.check(target.slot) },
            enabled = target.connection !is InstallTarget.Connection.Checking &&
                target.address.isNotBlank(),
            showDivider = target.connection !is InstallTarget.Connection.Unchecked,
        )
        ConnectionVerdict(model, target)
        SwapRow(target) { size -> model.addSwap(target.slot, size) }
    }
}

@Composable
private fun AuthFields(model: InstallViewModel, target: InstallTarget) {
    val byPassword = target.secret is InstallTarget.Secret.Password
    GroupedRow {
        IOSSegmentedControl(
            segments = listOf(false, true),
            selected = byPassword,
            modifier = Modifier.weight(1f),
            label = {
                stringResource(
                    if (it) R.string.install_auth_password else R.string.install_auth_key
                )
            },
            onSelect = { wantsPassword ->
                model.edit(target.slot) {
                    when {
                        !wantsPassword -> it.copy(secret = InstallTarget.Secret.AppKey)
                        it.secret is InstallTarget.Secret.Password -> it
                        else -> it.copy(secret = InstallTarget.Secret.Password(""))
                    }
                }
            },
        )
    }
    (target.secret as? InstallTarget.Secret.Password)?.let { password ->
        FieldRow(
            label = stringResource(R.string.install_auth_password),
            value = password.value,
            onValueChange = { value ->
                model.edit(target.slot) {
                    it.copy(secret = InstallTarget.Secret.Password(value))
                }
            },
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
        )
    }
}

@Composable
private fun ConnectionVerdict(model: InstallViewModel, target: InstallTarget) {
    when (val connection = target.connection) {
        InstallTarget.Connection.Unchecked -> Unit
        InstallTarget.Connection.Checking -> VerdictRow(
            stringResource(R.string.install_checking),
            Gryonix.colors.secondaryLabel,
        )
        InstallTarget.Connection.Ok -> VerdictRow(
            stringResource(R.string.install_reachable),
            Gryonix.colors.success,
        )
        is InstallTarget.Connection.Failed -> VerdictRow(
            connection.reason,
            Gryonix.colors.danger,
        )
        InstallTarget.Connection.NotAdministrator -> VerdictRow(
            stringResource(R.string.sudo_not_administrator),
            Gryonix.colors.danger,
        )
        is InstallTarget.Connection.NeedsSudoPassword -> SudoPasswordRows(
            username = target.username.trim(),
            problem = connection.problem,
            onSubmit = { model.grantSudo(target.slot, it) },
        )
    }
}

@Composable
private fun SudoPasswordRows(username: String, problem: SudoProblem?, onSubmit: (String) -> Unit) {
    var password by remember { mutableStateOf("") }
    VerdictRow(stringResource(R.string.sudo_needed, username), Gryonix.colors.secondaryLabel)
    SudoPasswordField(password) { password = it }
    ActionRow(
        text = stringResource(R.string.sudo_allow),
        onClick = { onSubmit(password); password = "" },
        enabled = password.isNotEmpty(),
        showDivider = problem != null,
    )
    sudoProblemText(problem)?.let { VerdictRow(it, Gryonix.colors.danger) }
}

@Composable
internal fun VerdictRow(text: String, color: androidx.compose.ui.graphics.Color) {
    GroupedRow(showDivider = false) {
        Text(text, style = MaterialTheme.typography.bodyMedium, color = color)
    }
}

// ----------------------------------------------------------------- Running

private fun androidx.compose.foundation.lazy.LazyListScope.running(
    model: InstallViewModel,
    state: InstallState,
) {
    item {
        LinearProgressIndicator(
            progress = { state.progress.toFloat() },
            color = Gryonix.colors.accent,
            trackColor = Gryonix.colors.trackFill,
            strokeCap = StrokeCap.Round,
            gapSize = 0.dp,
            drawStopIndicator = {},
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Metrics.listInset)
                .height(4.dp),
        )
    }
    if (state.stepTotal > 0) {
        item {
            Caption("${(state.progress * 100).roundToInt()}%")
        }
    }
    if (state.stage.isNotEmpty()) {
        item {
            Text(
                state.stage,
                style = MaterialTheme.typography.titleLarge,
                color = Gryonix.colors.label,
                modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
            )
        }
    }
    logSection(state)
    item {
        GroupedSection(footer = stringResource(R.string.install_stop_hint)) {
            ActionRow(
                text = stringResource(R.string.install_stop_following),
                onClick = { model.stopFollowing() },
                showDivider = false,
            )
        }
    }
}

// ----------------------------------------------------------------- Failure

private fun androidx.compose.foundation.lazy.LazyListScope.failure(
    model: InstallViewModel,
    state: InstallState,
    reason: String,
) {
    item {
        Text(
            reason,
            style = MaterialTheme.typography.bodyLarge,
            color = Gryonix.colors.danger,
            modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
        )
    }
    when {
        state.sawPortConflict -> item {
            Caption(stringResource(R.string.install_ports_hint))
        }
        state.sawDNSCheckFailure -> {
            item { Caption(stringResource(R.string.install_dns_hint)) }
            model.dnsRecords?.let { records -> item { CopyableCommand(records) } }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    ProminentButton(
                        text = stringResource(R.string.install_retry),
                        onClick = { model.retry() },
                        modifier = Modifier.padding(horizontal = Metrics.listInset),
                    )
                    GroupedSection {
                        ActionRow(
                            text = stringResource(R.string.install_retry_skip_dns),
                            onClick = { model.retry(skipDNSCheck = true) },
                            showDivider = false,
                        )
                    }
                }
            }
        }
        else -> {
            item {
                ProminentButton(
                    text = stringResource(R.string.install_retry),
                    onClick = { model.retry() },
                    modifier = Modifier.padding(horizontal = Metrics.listInset),
                )
            }
            item { Caption(stringResource(R.string.install_retry_hint)) }
        }
    }
    logSection(state)
}

// ---------------------------------------------------------------- Finished

private fun androidx.compose.foundation.lazy.LazyListScope.finished(
    state: InstallState,
    onOpenServer: () -> Unit,
) {
    item {
        Text(
            stringResource(R.string.install_finished),
            style = MaterialTheme.typography.displayMedium,
            color = Gryonix.colors.label,
            modifier = Modifier.padding(horizontal = Metrics.listInset),
        )
    }
    item {
        ProminentButton(
            text = stringResource(R.string.install_open_server),
            onClick = onOpenServer,
            modifier = Modifier.padding(horizontal = Metrics.listInset),
        )
    }
    if (state.installWarnings.isNotEmpty()) {
        item {
            SectionTitle(stringResource(R.string.install_warnings_header))
            Caption(stringResource(R.string.install_warnings_hint))
        }
        items(state.installWarnings.size) { index ->
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                modifier = Modifier.padding(horizontal = Metrics.listInset, vertical = 4.dp),
            ) {
                Icon(
                    Icons.Filled.Warning,
                    contentDescription = null,
                    tint = Gryonix.colors.warning,
                    modifier = Modifier.size(18.dp),
                )
                Text(
                    state.installWarnings[index],
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.label,
                )
            }
        }
    }
    if (state.reports.isNotEmpty()) {
        item {
            SectionTitle(stringResource(R.string.install_report))
            Caption(stringResource(R.string.install_report_hint))
        }
        items(state.reports.size) { index ->
            CopyableCommand(state.reports[index].text)
        }
    }
    logSection(state)
}

// ------------------------------------------------------------------ Pieces

private fun androidx.compose.foundation.lazy.LazyListScope.logSection(state: InstallState) {
    if (state.log.isEmpty()) return
    item { SectionTitle(stringResource(R.string.install_log)) }
    items(state.log.size) { index ->
        Text(
            state.log[state.log.size - 1 - index],
            style = MaterialTheme.typography.bodySmall,
            fontFamily = FontFamily.Monospace,
            color = Gryonix.colors.secondaryLabel,
            modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
        )
    }
}

@Composable
private fun CopyableCommand(text: String) {
    // The install report is every credential the setup just generated.
    val copySecret = rememberSecretClipboard()
    var copied by remember { mutableStateOf(false) }
    GroupedSection {
        GroupedRow {
            SelectionContainer {
                Text(
                    text,
                    style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace,
                    color = Gryonix.colors.label,
                )
            }
        }
        ActionRow(
            text = stringResource(if (copied) R.string.install_copied else R.string.install_copy),
            onClick = {
                copySecret(text)
                copied = true
            },
            showDivider = false,
        )
    }
}
