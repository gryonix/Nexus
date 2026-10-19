package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Email
import androidx.compose.material.icons.filled.Key
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.AlertFields
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.mail.MailboxPassword
import com.skaymer.gryonixnexus.app.mail.MailboxesViewModel
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.Mailbox

@Composable
fun MailboxesCard(onOpen: () -> Unit, showDivider: Boolean = true) {
    ValueRow(
        title = stringResource(R.string.mailboxes),
        value = null,
        onClick = onOpen,
        showDivider = showDivider,
        leading = {
            Icon(Icons.Filled.Email, contentDescription = null, modifier = Modifier.size(22.dp))
        },
    )
}

/** The mailboxes of one server */
@Composable
fun MailboxesDialog(
    deployment: Deployment,
    mailboxes: MailboxesViewModel,
    onClose: () -> Unit,
) {
    val state by mailboxes.state.collectAsState()
    var adding by remember(deployment.id) { mutableStateOf(false) }
    var changing by remember(deployment.id) { mutableStateOf<Mailbox?>(null) }
    var deleting by remember(deployment.id) { mutableStateOf<Mailbox?>(null) }

    LaunchedEffect(deployment.id) { mailboxes.load(deployment) }

    IOSSheet(
        title = stringResource(R.string.mailboxes_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_done),
        action = SheetAction(
            title = stringResource(R.string.mailboxes_add),
            enabled = !state.isWorking,
            onSelect = { adding = true },
        ),
    ) {
        when {
            state.isLoading && state.mailboxes.isEmpty() -> Row(
                Modifier.padding(horizontal = Metrics.listInset + 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CircularProgressIndicator(
                    Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = Gryonix.colors.tertiaryLabel,
                )
                Text(
                    stringResource(R.string.mailboxes_loading),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
            state.saysThereAreNone -> Text(
                stringResource(R.string.mailboxes_none),
                style = MaterialTheme.typography.bodyMedium,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
            )
            else -> GroupedSection(
                footer = if (state.errorMessage == MailboxesViewModel.VAULT_FAILURE) stringResource(R.string.mailbox_vault_failure) else state.errorMessage ?: stringResource(R.string.mailboxes_footer),
            ) {
                state.mailboxes.forEach { mailbox ->
                    MailboxRow(
                        mailbox,
                        onChangePassword = { changing = mailbox },
                        onDelete = { deleting = mailbox },
                        showDivider = mailbox != state.mailboxes.last(),
                    )
                }
            }
        }
    }

    if (adding) {
        MailboxEditorDialog(
            domains = MailboxesViewModel.domains(deployment),
            existing = null,
            onCancel = { adding = false },
            onConfirm = { address, password ->
                adding = false
                mailboxes.add(deployment, address, password)
            },
        )
    }
    changing?.let { mailbox ->
        MailboxEditorDialog(
            domains = emptyList(),
            existing = mailbox.address,
            onCancel = { changing = null },
            onConfirm = { address, password ->
                changing = null
                mailboxes.setPassword(deployment, address, password)
            },
        )
    }
    deleting?.let { mailbox ->
        ConfirmAlert(
            title = stringResource(R.string.mailboxes_delete_title),
            message = stringResource(R.string.mailboxes_delete_message, mailbox.address),
            confirm = stringResource(R.string.mailboxes_delete),
            cancel = stringResource(R.string.containers_cancel),
            destructive = true,
            onConfirm = {
                deleting = null
                mailboxes.delete(deployment, mailbox.address)
            },
            onCancel = { deleting = null },
        )
    }
}

@Composable
private fun MailboxRow(
    mailbox: Mailbox,
    onChangePassword: () -> Unit,
    onDelete: () -> Unit,
    showDivider: Boolean = true,
) {
    val colors = Gryonix.colors
    GroupedRow(
        showDivider = showDivider,
        trailing = {
            IconButton(
                onClick = onChangePassword,
                enabled = mailbox.isManageable,
                modifier = Modifier.size(28.dp),
            ) {
                Icon(
                    Icons.Filled.Key,
                    contentDescription = stringResource(R.string.mailboxes_change_password),
                    tint = if (mailbox.isManageable) colors.accent else colors.tertiaryLabel,
                    modifier = Modifier.size(18.dp),
                )
            }
            IconButton(
                onClick = onDelete,
                enabled = mailbox.isManageable,
                modifier = Modifier.size(28.dp),
            ) {
                Icon(
                    Icons.Filled.Delete,
                    contentDescription = stringResource(R.string.mailboxes_delete),
                    tint = if (mailbox.isManageable) colors.danger else colors.tertiaryLabel,
                    modifier = Modifier.size(18.dp),
                )
            }
        },
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                mailbox.address,
                style = MaterialTheme.typography.bodyLarge,
                color = colors.label,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            when {
                mailbox.detail != null -> Text(
                    mailbox.detail!!,
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.secondaryLabel,
                    maxLines = 1,
                )
                !mailbox.isManageable -> Text(
                    stringResource(R.string.mailboxes_unmanageable),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.tertiaryLabel,
                )
            }
        }
    }
}

/** Creates a mailbox, or replaces its password */
@Composable
fun MailboxEditorDialog(
    domains: List<String>,
    existing: String?,
    onCancel: () -> Unit,
    onConfirm: (String, String) -> Unit,
) {
    var localPart by remember { mutableStateOf("") }
    var domain by remember { mutableStateOf(domains.firstOrNull().orEmpty()) }
    var password by remember { mutableStateOf("") }
    var revealed by remember { mutableStateOf(false) }
    var domainMenu by remember { mutableStateOf(false) }
    val copySecret = rememberSecretClipboard()

    val address = existing ?: "${localPart.trim()}@$domain"
    val canSubmit = if (existing == null) {
        MailboxesViewModel.canCreate(address, password)
    } else {
        MailboxesViewModel.canChangePassword(password)
    }

    IOSAlert(
        title = stringResource(
            if (existing == null) R.string.mailboxes_new else R.string.mailboxes_new_password
        ),
        // The two rules, said once, under the fields they govern.
        message = if (existing == null) {
            stringResource(R.string.mailboxes_address_rule) + "\n" +
                stringResource(R.string.mailboxes_password_rule)
        } else {
            stringResource(R.string.mailboxes_password_rule)
        },
        onDismiss = onCancel,
        actions = listOf(
            AlertAction(stringResource(R.string.containers_cancel), onSelect = onCancel),
            AlertAction(
                stringResource(
                    if (existing == null) R.string.mailboxes_create else R.string.mailboxes_change
                ),
                preferred = true,
                enabled = canSubmit,
                onSelect = { onConfirm(address, password) },
            ),
        ),
    ) {
        AlertFields {
            if (existing == null) {
                FieldRow(
                    label = stringResource(R.string.mailboxes_name),
                    value = localPart,
                    onValueChange = { localPart = it },
                )
                if (domains.size > 1) {
                    Box {
                        ValueRow(
                            title = stringResource(R.string.domain_label),
                            value = "@$domain",
                            onClick = { domainMenu = true },
                        )
                        DropdownMenu(
                            expanded = domainMenu,
                            onDismissRequest = { domainMenu = false },
                        ) {
                            domains.forEach { candidate ->
                                DropdownMenuItem(
                                    text = { Text(candidate) },
                                    onClick = { domain = candidate; domainMenu = false },
                                )
                            }
                        }
                    }
                } else {
                    ValueRow(
                        title = stringResource(R.string.domain_label),
                        value = "@$domain",
                        onClick = null,
                    )
                }
            } else {
                ValueRow(title = existing, value = null, onClick = null)
            }
            FieldRow(
                label = stringResource(R.string.mailboxes_password),
                value = password,
                onValueChange = { password = it },
                visualTransformation = if (revealed) {
                    androidx.compose.ui.text.input.VisualTransformation.None
                } else {
                    PasswordVisualTransformation()
                },
            )
            ActionRow(
                text = stringResource(R.string.mailboxes_generate),
                onClick = {
                    password = MailboxPassword.generate()
                    revealed = true
                },
                showDivider = password.isNotEmpty(),
            )
            if (password.isNotEmpty()) {
                ActionRow(
                    text = stringResource(R.string.mailboxes_copy),
                    onClick = { copySecret(password) },
                    showDivider = false,
                )
            }
        }
    }
}
