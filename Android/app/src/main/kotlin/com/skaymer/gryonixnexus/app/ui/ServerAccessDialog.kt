package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.AdvancedSection
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.secrets.AppIdentities
import com.skaymer.gryonixnexus.servercontrol.AccessGrantCommand
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun ServerAccessDialog(
    deployment: Deployment,
    secrets: SecretStore,
    onCredentialsChanged: () -> Unit,
    onClose: () -> Unit,
) {
    val clipboard = LocalClipboardManager.current
    val identities = remember(secrets) { AppIdentities(secrets) }
    var publicKey by remember(deployment.id) { mutableStateOf("") }
    var keyError by remember(deployment.id) { mutableStateOf<String?>(null) }
    var confirmingNewKey by remember(deployment.id) { mutableStateOf(false) }
    var confirmingPinReset by remember(deployment.id) { mutableStateOf(false) }

    LaunchedEffect(deployment.id) {
        runCatching { withContext(Dispatchers.IO) { identities.publicKey(deployment.id) } }
            .onSuccess { publicKey = it; keyError = null }
            .onFailure { keyError = it.message ?: it::class.simpleName }
    }

    IOSSheet(
        title = stringResource(R.string.server_access_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_done),
    ) {
        GroupedSection(footer = keyError ?: stringResource(R.string.access_key_hint)) {
            if (publicKey.isNotEmpty()) {
                ActionRow(
                    text = stringResource(R.string.access_copy_command),
                    onClick = {
                        clipboard.setText(
                            AnnotatedString(AccessGrantCommand.command(publicKey))
                        )
                    },
                )
            }
            ActionRow(
                text = stringResource(R.string.access_new_key),
                onClick = { confirmingNewKey = true },
                danger = true,
                showDivider = false,
            )
        }
        if (publicKey.isNotEmpty()) {
            AdvancedSection {
                GroupedRow {
                    SelectionContainer {
                        Text(
                            publicKey,
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace,
                            color = Gryonix.colors.label,
                            maxLines = 3,
                        )
                    }
                }
                ActionRow(
                    text = stringResource(R.string.access_copy_key),
                    onClick = { clipboard.setText(AnnotatedString(publicKey)) },
                    showDivider = false,
                )
            }
        }
        GroupedSection(footer = stringResource(R.string.access_pins_hint)) {
            ActionRow(
                text = stringResource(R.string.access_reset_pins),
                onClick = { confirmingPinReset = true },
                danger = true,
                showDivider = false,
            )
        }
    }

    if (confirmingNewKey) {
        ConfirmAlert(
            title = stringResource(R.string.access_new_key_title),
            message = stringResource(R.string.access_new_key_warning),
            confirm = stringResource(R.string.access_new_key),
            destructive = true,
            onConfirm = {
                confirmingNewKey = false
                runCatching { identities.regenerate(deployment.id) }
                    .onSuccess {
                        publicKey = it.publicKeyOpenSSH
                        keyError = null
                        onCredentialsChanged()
                    }
                    .onFailure { keyError = it.message ?: it::class.simpleName }
            },
            onCancel = { confirmingNewKey = false },
        )
    }

    if (confirmingPinReset) {
        ConfirmAlert(
            title = stringResource(R.string.access_reset_pins_title),
            message = stringResource(R.string.access_reset_pins_warning),
            confirm = stringResource(R.string.access_reset_pins),
            destructive = true,
            onConfirm = {
                confirmingPinReset = false
                val store = DeploymentSecrets(secrets, deployment.id)
                deployment.nodes.forEach { store.forgetHostKeyPin(it) }
                onCredentialsChanged()
            },
            onCancel = { confirmingPinReset = false },
        )
    }
}
