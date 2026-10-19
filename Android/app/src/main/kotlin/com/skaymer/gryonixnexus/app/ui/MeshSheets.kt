package com.skaymer.gryonixnexus.app.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.CircularProgressIndicator
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.LoadingRow
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.agentcontrol.MeshNode
import com.skaymer.gryonixnexus.app.mesh.MeshState
import com.skaymer.gryonixnexus.app.mesh.MeshViewModel
import com.skaymer.gryonixnexus.servercontrol.Deployment
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun MeshCard(mesh: MeshViewModel, onOpen: () -> Unit, showDivider: Boolean = true) {
    val state by mesh.state.collectAsState()
    ValueRow(
        title = stringResource(R.string.mesh),
        value = if (state.hasAnswered) {
            stringResource(R.string.mesh_count, state.nodes.size)
        } else {
            null
        },
        onClick = onOpen,
        showDivider = showDivider,
    )
}

@Composable
fun MeshDialog(deployment: Deployment, mesh: MeshViewModel, onClose: () -> Unit) {
    val state by mesh.state.collectAsState()
    LaunchedEffect(deployment.id) { mesh.load(deployment) }

    var pendingRemoval by remember(deployment.id) { mutableStateOf<MeshNode?>(null) }

    IOSSheet(
        title = stringResource(R.string.mesh),
        onClose = onClose,
        closeLabel = stringResource(R.string.close),
    ) {
        when {
            state.isBusy && state.nodes.isEmpty() -> LoadingRow()
            state.saysThereAreNone -> Muted(stringResource(R.string.mesh_none))
            else -> GroupedSection(
                footer = state.errorMessage
                    ?: state.notice
                    ?: stringResource(R.string.mesh_devices_hint),
            ) {
                state.nodes.forEach { node ->
                    DeviceRow(
                        node,
                        showDivider = node != state.nodes.last(),
                    ) { pendingRemoval = node }
                }
            }
        }

        AddDeviceSection(deployment, mesh, state)
        PublishedNamesSection(deployment, mesh, state)
    }

    state.joinKey?.let { key ->
        JoinKeyDialog(
            command = MeshViewModel.joinCommand(deployment, key),
            keyText = key.key,
            expiresAt = key.expiresAt?.let { formatter.format(it) },
        ) {
            mesh.clearJoinKey()
            mesh.load(deployment)
        }
    }

    pendingRemoval?.let { node ->
        ConfirmAlert(
            title = stringResource(R.string.mesh_remove),
            message = stringResource(R.string.mesh_remove_confirm, node.name),
            confirm = stringResource(R.string.mesh_remove),
            cancel = stringResource(R.string.containers_cancel),
            destructive = true,
            onConfirm = {
                mesh.remove(deployment, node.id)
                pendingRemoval = null
            },
            onCancel = { pendingRemoval = null },
        )
    }
}

@Composable
private fun AddDeviceSection(deployment: Deployment, mesh: MeshViewModel, state: MeshState) {
    GroupedSection {
        ActionRow(
            text = stringResource(R.string.mesh_add),
            enabled = !state.isMinting,
            onClick = { mesh.mintJoinKey(deployment) },
            showDivider = false,
            leading = if (!state.isMinting) {
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
    }
}

@Composable
private fun PublishedNamesSection(deployment: Deployment, mesh: MeshViewModel, state: MeshState) {
    GroupedSection(
        header = stringResource(R.string.mesh_published_header),
        note = stringResource(R.string.mesh_publish_hint),
    ) {
        ActionRow(
            text = stringResource(R.string.mesh_publish),
            onClick = { mesh.publishNames(deployment) },
            showDivider = state.publishedNames.isNotEmpty(),
        )
        state.publishedNames.forEach { record ->
            GroupedRow(
                showDivider = record != state.publishedNames.last(),
                trailing = {
                    Text(
                        record.address,
                        style = MaterialTheme.typography.labelSmall,
                        fontFamily = FontFamily.Monospace,
                        color = Gryonix.colors.secondaryLabel,
                    )
                },
            ) {
                Text(
                    record.name,
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.label,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

@Composable
private fun DeviceRow(node: MeshNode, showDivider: Boolean = true, onRemove: () -> Unit) {
    val colors = Gryonix.colors
    GroupedRow(
        showDivider = showDivider,
        leading = {
            Box(
                Modifier
                    .size(8.dp)
                    .background(
                        if (node.isOnline) colors.success else colors.tertiaryLabel,
                        CircleShape
                    )
            )
        },
        trailing = {
            PlainButton(
                text = stringResource(R.string.mesh_remove),
                onClick = onRemove,
                danger = true,
            )
        },
    ) {
        Column(Modifier.weight(1f)) {
            Text(
                node.name,
                style = MaterialTheme.typography.bodyLarge,
                color = colors.label,
            )
            Text(
                listOfNotNull(
                    node.addresses.firstOrNull(),
                    node.user.takeIf { it.isNotEmpty() },
                ).joinToString("  ·  "),
                style = MaterialTheme.typography.labelSmall,
                fontFamily = FontFamily.Monospace,
                color = colors.secondaryLabel,
            )
        }
    }
}

/** The join key, with the command that uses it */
@Composable
private fun JoinKeyDialog(
    command: String,
    keyText: String,
    expiresAt: String?,
    onClose: () -> Unit,
) {
    val context = LocalContext.current
    IOSSheet(
        title = stringResource(R.string.mesh_add),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_done),
    ) {
        GroupedSection(
            header = stringResource(R.string.mesh_join_key),
            footer = if (expiresAt != null) {
                stringResource(R.string.mesh_join_key_until, expiresAt)
            } else {
                stringResource(R.string.mesh_join_key_once)
            },
        ) {
            GroupedRow(showDivider = false) {
                SelectionContainer {
                    Text(
                        keyText,
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        color = Gryonix.colors.label,
                    )
                }
            }
        }
        GroupedSection(
            header = stringResource(R.string.mesh_on_the_device),
            note = stringResource(R.string.mesh_on_the_device_hint),
        ) {
            GroupedRow {
                SelectionContainer {
                    Text(
                        command,
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        color = Gryonix.colors.label,
                    )
                }
            }
            ActionRow(
                text = stringResource(R.string.mesh_copy_command),
                onClick = { copy(context, command) },
                showDivider = false,
            )
        }
    }
}

private fun copy(context: Context, text: String) {
    copySecret(context, text)
}

@Composable
private fun Muted(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = Gryonix.colors.secondaryLabel,
        modifier = Modifier.padding(horizontal = Metrics.listInset + 4.dp),
    )
}

private val formatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("d MMM yyyy HH:mm").withZone(ZoneId.systemDefault())
