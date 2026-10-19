package com.skaymer.gryonixnexus.app.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.ui.graphics.SolidColor
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.app.security.GatedAction
import com.skaymer.gryonixnexus.app.security.rememberGuard
import com.skaymer.gryonixnexus.app.access.AccessAccount
import com.skaymer.gryonixnexus.app.access.AccessSync
import com.skaymer.gryonixnexus.app.access.AccessHostTitle
import com.skaymer.gryonixnexus.app.access.AccessViewModel
import com.skaymer.gryonixnexus.servercontrol.Deployment

@Composable
fun AccessCard(onOpen: () -> Unit, showDivider: Boolean = true) {
    ValueRow(
        title = stringResource(R.string.logins_title),
        value = null,
        onClick = onOpen,
        showDivider = showDivider,
        leading = { Icon(Icons.Filled.Lock, contentDescription = null, modifier = Modifier.size(22.dp)) },
    )
}

@Composable
fun AccessDialog(deployment: Deployment, access: AccessViewModel, onClose: () -> Unit) {
    val state by access.state.collectAsState()
    val context = LocalContext.current
    LaunchedEffect(deployment.id) { access.load(deployment) }
    DisposableEffect(deployment.id) { onDispose { access.reset() } }

    val showsHost = access.showsHost

    IOSSheet(
        title = stringResource(R.string.logins_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_done),
        action = if (state.accounts.isEmpty()) {
            null
        } else {
            SheetAction(
                title = stringResource(
                    if (state.justSaved) R.string.logins_saved else R.string.logins_save
                ),
                enabled = !state.justSaved,
                onSelect = { access.save(deployment) },
            )
        },
    ) {
        when {
            state.isLoading -> Row(
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
                    stringResource(R.string.backups_loading),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
            state.saysThereIsNothing ->
                AccessMuted(stringResource(R.string.logins_no_report))
            state.saysThereAreNoLogins ->
                AccessMuted(stringResource(R.string.logins_no_logins))
            else -> {
                AccessSyncLine(state.sync)
                state.accounts.forEach { account ->
                    AccountCard(deployment, account, showsHost, state.revealed, access, context)
                }
            }
        }
    }
}

/** One line saying where these values live */
@Composable
private fun AccessSyncLine(sync: AccessSync) {
    val text = when (sync) {
        AccessSync.Synced -> stringResource(R.string.logins_sync_server)
        AccessSync.LocalOnly -> stringResource(R.string.logins_sync_local)
        AccessSync.SignedOut -> stringResource(R.string.logins_sync_signed_out)
        AccessSync.Unidentified -> stringResource(R.string.logins_sync_unidentified)
        is AccessSync.Failed -> stringResource(R.string.logins_sync_failed)
    }
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = if (sync is AccessSync.Synced || sync is AccessSync.LocalOnly) {
            Gryonix.colors.secondaryLabel
        } else {
            Gryonix.colors.warning
        },
    )
}

@Composable
private fun AccountCard(
    deployment: Deployment,
    account: AccessAccount,
    showsHost: Boolean,
    revealed: Set<String>,
    access: AccessViewModel,
    context: Context,
) {
    GroupedSection(
        header = if (showsHost) {
            "${hostTitle(deployment, account.host)} · ${account.title}"
        } else {
            account.title
        },
    ) {
        Column(Modifier.fillMaxWidth()) {
            account.website?.let { site ->
                ReadOnlyRow(stringResource(R.string.logins_website), site, context)
            }
            EditableRow(
                label = stringResource(
                    if (account.isVaultwarden) R.string.logins_email else R.string.logins_login
                ),
                value = account.login,
                fieldID = account.id + "-login",
                secret = false,
                revealed = revealed,
                access = access,
                context = context,
                onChange = { access.editLogin(account.id, it) },
            )
            EditableRow(
                label = stringResource(
                    if (account.isVaultwarden) {
                        R.string.logins_master_password
                    } else {
                        R.string.logins_password
                    }
                ),
                value = account.password,
                fieldID = account.id + "-password",
                secret = true,
                revealed = revealed,
                access = access,
                context = context,
                onChange = { access.editPassword(account.id, it) },
                isLast = !account.hasToken,
            )
            if (account.hasToken) {
                EditableRow(
                    label = stringResource(R.string.logins_admin_token),
                    value = account.token,
                    fieldID = account.id + "-token",
                    secret = true,
                    revealed = revealed,
                    access = access,
                    context = context,
                    onChange = { access.editToken(account.id, it) },
                    isLast = true,
                )
            }
        }
    }
}

@Composable
private fun ReadOnlyRow(label: String, value: String, context: Context) {
    GroupedRow(trailing = { CopyButton(value, context) }) {
        Column(Modifier.weight(1f)) {
            Text(
                label,
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.secondaryLabel,
            )
            Text(
                value,
                style = MaterialTheme.typography.bodyMedium,
                fontFamily = FontFamily.Monospace,
                color = Gryonix.colors.label,
            )
        }
    }
}

@Composable
private fun EditableRow(
    label: String,
    value: String,
    fieldID: String,
    secret: Boolean,
    revealed: Set<String>,
    access: AccessViewModel,
    context: Context,
    onChange: (String) -> Unit,
    isLast: Boolean = false,
) {
    val isRevealed = !secret || fieldID in revealed
    val guard = rememberGuard()
    GroupedRow(
        showDivider = !isLast,
        trailing = {
            if (secret) {
                PlainButton(
                    text = stringResource(
                        if (isRevealed) R.string.logins_hide else R.string.logins_reveal
                    ),
                    onClick = {
                        if (fieldID in revealed) {
                            access.hide(fieldID)
                        } else {
                            guard(GatedAction.REVEAL, label) { access.reveal(fieldID) }
                        }
                    },
                )
            }
            CopyButton(value, context)
        },
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodySmall,
            color = Gryonix.colors.secondaryLabel,
            modifier = Modifier.widthIn(max = 110.dp),
        )
        BasicTextField(
            value = value,
            onValueChange = onChange,
            singleLine = true,
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
                autoCorrectEnabled = false
            ),
            visualTransformation = if (isRevealed) {
                VisualTransformation.None
            } else {
                PasswordVisualTransformation()
            },
            textStyle = MaterialTheme.typography.bodyMedium.copy(
                color = Gryonix.colors.label,
                fontFamily = if (isRevealed) FontFamily.Monospace else FontFamily.Default,
            ),
            cursorBrush = SolidColor(Gryonix.colors.accent),
            modifier = Modifier.weight(1f),
        )
    }
}
@Composable
private fun CopyButton(value: String, context: Context) {
    IconButton(
        onClick = { copyAccess(context, value) },
        enabled = value.isNotEmpty(),
        modifier = Modifier.size(28.dp),
    ) {
        Icon(
            Icons.Filled.ContentCopy,
            contentDescription = stringResource(R.string.logins_copy),
            tint = if (value.isEmpty()) Gryonix.colors.tertiaryLabel else Gryonix.colors.accent,
            modifier = Modifier.size(18.dp),
        )
    }
}

@Composable
private fun hostTitle(deployment: Deployment, host: String): String =
    when (val title = AccessHostTitle.of(deployment, host)) {
        AccessHostTitle.VPS -> "VPS"
        AccessHostTitle.LocalServer -> stringResource(R.string.logins_local_server)
        AccessHostTitle.Server -> stringResource(R.string.logins_server)
        is AccessHostTitle.Named -> title.name
    }

private fun copyAccess(context: Context, text: String) {
    copySecret(context, text)
}

@Composable
private fun AccessMuted(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = Gryonix.colors.secondaryLabel,
        modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
    )
}
