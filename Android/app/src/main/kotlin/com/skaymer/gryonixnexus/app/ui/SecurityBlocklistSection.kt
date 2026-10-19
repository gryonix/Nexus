package com.skaymer.gryonixnexus.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.style.TextOverflow
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.security.SecurityScreenState
import com.skaymer.gryonixnexus.app.security.SecurityViewModel
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.AlertFields
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostSecurityAllowlist
import com.skaymer.gryonixnexus.servercontrol.HostSecurityDecisions

@Composable
fun SecurityBlocklistSection(
    deployment: Deployment,
    security: SecurityViewModel,
    state: SecurityScreenState,
) {
    var expanded by remember { mutableStateOf(false) }
    var adding by remember { mutableStateOf<AddTarget?>(null) }
    var confirmingLift by remember { mutableStateOf<HostSecurityDecisions.Decision?>(null) }

    GroupedRow(
        onClick = {
            expanded = !expanded
            if (expanded && state.decisions == null) security.loadLists(deployment)
        },
        trailing = { DisclosureChevron() },
        showDivider = false,
    ) { RowLabel(stringResource(R.string.security_blocked_addresses)) }

    AnimatedVisibility(expanded) {
        Column {
            AllowlistRows(deployment, security, state) { adding = AddTarget.ALLOW }
            ActionRow(
                text = stringResource(R.string.security_block_an_address),
                onClick = { adding = AddTarget.BAN },
                enabled = !state.listBusy,
            )
            DecisionRows(state) { confirmingLift = it }
            state.listFailure?.let { failure ->
                GroupedRow(showDivider = false) {
                    Text(
                        failure,
                        style = MaterialTheme.typography.bodySmall,
                        color = Gryonix.colors.danger,
                    )
                }
            }
        }
    }

    LaunchedEffect(deployment.id) { if (expanded) security.loadLists(deployment) }

    confirmingLift?.let { decision ->
        ConfirmAlert(
            title = stringResource(R.string.security_lift_block_title),
            message = stringResource(R.string.security_lift_block_message, decision.value),
            confirm = stringResource(R.string.security_lift),
            onConfirm = {
                security.setBan(deployment, banned = false, value = decision.value, decisionId = decision.decisionId)
                confirmingLift = null
            },
            onCancel = { confirmingLift = null },
        )
    }

    adding?.let { target ->
        SecurityAddressAlert(
            isBan = target == AddTarget.BAN,
            suggestions = suggestions(state),
            onDismiss = { adding = null },
            onSubmit = { value, seconds, comment ->
                if (target == AddTarget.BAN) {
                    security.setBan(deployment, banned = true, value = value, durationSeconds = seconds, reason = comment)
                } else {
                    security.setAllowed(deployment, allowed = true, value = value, comment = comment, durationSeconds = seconds)
                }
                adding = null
            },
        )
    }
}

private enum class AddTarget { BAN, ALLOW }

private fun suggestions(state: SecurityScreenState): List<String> {
    val connected = state.decisions?.sshClientIps ?: state.allowlist?.sshClientIps ?: emptyList()
    val allowed = state.allowlist?.entries?.map { it.value }.orEmpty()
    return connected.filter { it !in allowed }
}

@Composable
private fun AllowlistRows(
    deployment: Deployment,
    security: SecurityViewModel,
    state: SecurityScreenState,
    onAdd: () -> Unit,
) {
    val allowlist = state.allowlist ?: return
    if (!allowlist.isSupported) {
        GroupedRow {
            Text(
                stringResource(R.string.security_allowlist_unsupported),
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.secondaryLabel,
            )
        }
        return
    }
    GroupedRow {
        Text(
            stringResource(R.string.security_never_blocked),
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.secondaryLabel,
        )
    }
    ActionRow(
        text = stringResource(R.string.security_protect_an_address),
        onClick = onAdd,
        enabled = !state.listBusy,
    )
    allowlist.entries.forEach { entry -> AllowedRow(deployment, security, state, entry) }
    if (allowlist.entries.isEmpty()) {
        GroupedRow {
            Text(
                stringResource(R.string.security_no_protected_address),
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.secondaryLabel,
            )
        }
    }
}

@Composable
private fun AllowedRow(
    deployment: Deployment,
    security: SecurityViewModel,
    state: SecurityScreenState,
    entry: HostSecurityAllowlist.Entry,
) {
    GroupedRow(
        onClick = if (state.listBusy) null else {
            { security.setAllowed(deployment, allowed = false, value = entry.value) }
        },
        trailing = {
            Text(
                stringResource(R.string.security_remove),
                style = MaterialTheme.typography.bodyMedium,
                color = Gryonix.colors.danger,
            )
        },
    ) {
        Column {
            Text(entry.value, style = MaterialTheme.typography.bodyLarge, color = Gryonix.colors.label)
            if (entry.comment.isNotEmpty()) {
                Text(
                    entry.comment,
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun DecisionRows(
    state: SecurityScreenState,
    onLift: (HostSecurityDecisions.Decision) -> Unit,
) {
    val lists = state.decisions ?: return
    if (lists.decisions.isEmpty()) {
        GroupedRow {
            Text(
                stringResource(R.string.security_nothing_blocked),
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.secondaryLabel,
            )
        }
        return
    }
    lists.decisions.forEach { decision ->
        GroupedRow(
            onClick = if (state.listBusy) null else { { onLift(decision) } },
            trailing = {
                Text(
                    decision.expiresIn,
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.tertiaryLabel,
                )
            },
        ) {
            Column {
                Text(
                    listOf(CountryCatalog.flag(decision.country), decision.value)
                        .filter { it.isNotEmpty() }
                        .joinToString(" "),
                    style = MaterialTheme.typography.bodyLarge,
                    color = Gryonix.colors.label,
                )
                Text(
                    listOf(decision.readableReason, decision.asName)
                        .filter { it.isNotEmpty() }
                        .joinToString(" · "),
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun SecurityAddressAlert(
    isBan: Boolean,
    suggestions: List<String>,
    onDismiss: () -> Unit,
    onSubmit: (String, Long, String) -> Unit,
) {
    var value by remember { mutableStateOf("") }
    var comment by remember { mutableStateOf("") }
    var forever by remember { mutableStateOf(true) }

    IOSAlert(
        title = stringResource(
            if (isBan) R.string.security_block_an_address else R.string.security_protect_an_address,
        ),
        message = stringResource(
            if (isBan) R.string.security_block_message else R.string.security_protect_message,
        ),
        onDismiss = onDismiss,
        actions = listOf(
            AlertAction(stringResource(R.string.access_cancel), onSelect = onDismiss),
            AlertAction(
                stringResource(if (isBan) R.string.security_block else R.string.security_protect),
                destructive = isBan,
                preferred = !isBan,
                enabled = value.isNotBlank(),
                onSelect = { onSubmit(value.trim(), if (forever) 0L else 4 * 3600L, comment.trim()) },
            ),
        ),
    ) {
        AlertFields {
            FieldRow(
                label = stringResource(R.string.security_address),
                value = value,
                onValueChange = { value = it },
                placeholder = "203.0.113.9",
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None),
            )
            suggestions.forEach { address ->
                GroupedRow(onClick = { value = address }) {
                    Text(
                        address,
                        style = MaterialTheme.typography.bodyMedium,
                        color = Gryonix.colors.accent,
                    )
                }
            }
            ToggleRow(
                title = stringResource(
                    if (isBan) R.string.security_until_lifted else R.string.security_forever,
                ),
                checked = forever,
                onCheckedChange = { forever = it },
            )
            FieldRow(
                label = stringResource(
                    if (isBan) R.string.security_reason_optional else R.string.security_note_optional,
                ),
                value = comment,
                onValueChange = { comment = it },
                showDivider = false,
            )
        }
    }
}
