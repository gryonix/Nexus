package com.skaymer.gryonixnexus.app.ui

import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardType
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.BackupsViewModel
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.app.ui.design.StepperRow
import com.skaymer.gryonixnexus.servercontrol.BackupDestinationSettings
import com.skaymer.gryonixnexus.servercontrol.Deployment

@Composable
fun BackupDestinationSheet(
    deployment: Deployment,
    fleet: List<Deployment>,
    backups: BackupsViewModel,
    onClose: () -> Unit,
) {
    val state by backups.state.collectAsState()
    var draft by remember(state.destination.settings) { mutableStateOf(state.destination.settings) }
    var secret by remember(deployment.id) { mutableStateOf("") }
    val candidates = remember(fleet, deployment.id) { fleet.filter { it.id != deployment.id } }

    IOSSheet(
        title = stringResource(R.string.backup_destination),
        onClose = onClose,
        closeLabel = stringResource(R.string.group_cancel),
        action = SheetAction(
            title = stringResource(R.string.save),
            onSelect = {
                backups.saveDestination(deployment, draft, secret.ifEmpty { null })
                secret = ""
            },
        ),
    ) {
        GroupedSection(note = stringResource(R.string.backup_destination_note)) {
            ChoiceRow(
                title = stringResource(R.string.backup_destination_copies_go_to),
                value = stringResource(
                    when (draft.kind) {
                        BackupDestinationSettings.Kind.NONE -> R.string.backup_destination_nowhere
                        BackupDestinationSettings.Kind.SSH -> R.string.backup_destination_own_server
                        BackupDestinationSettings.Kind.S3 -> R.string.backup_destination_bucket_kind
                    },
                ),
                showDivider = false,
                options = listOf(
                    stringResource(R.string.backup_destination_nowhere) to {
                        draft = draft.copy(kind = BackupDestinationSettings.Kind.NONE)
                    },
                    stringResource(R.string.backup_destination_own_server) to {
                        draft = draft.copy(kind = BackupDestinationSettings.Kind.SSH)
                    },
                    stringResource(R.string.backup_destination_bucket_kind) to {
                        draft = draft.copy(kind = BackupDestinationSettings.Kind.S3)
                    },
                ),
            )
        }

        when (draft.kind) {
            BackupDestinationSettings.Kind.SSH -> {
                if (candidates.isNotEmpty()) {
                    GroupedSection(
                        header = stringResource(R.string.server_bastion_fleet),
                        note = stringResource(R.string.backup_destination_fleet_note),
                    ) {
                        candidates.forEachIndexed { index, server ->
                            CheckRow(
                                title = server.name,
                                subtitle = server.entry.host,
                                checked = draft.host == server.entry.host,
                                onClick = {
                                    draft = draft.copy(
                                        host = server.entry.host,
                                        port = server.entry.port,
                                        user = server.entry.user,
                                        path = draft.path.ifEmpty { "/srv/backups" },
                                    )
                                },
                                showDivider = index != candidates.lastIndex,
                            )
                        }
                    }
                }
                GroupedSection(
                    header = stringResource(R.string.backup_destination_where),
                    footer = stringResource(R.string.backup_destination_folder_note),
                ) {
                    FieldRow(
                        label = stringResource(R.string.host_label),
                        value = draft.host,
                        placeholder = "backup.example.com",
                        onValueChange = { draft = draft.copy(host = it) },
                    )
                    FieldRow(
                        label = stringResource(R.string.port_label),
                        value = draft.port.toString(),
                        onValueChange = {
                            draft = draft.copy(port = it.filter(Char::isDigit).toIntOrNull() ?: 22)
                        },
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    )
                    FieldRow(
                        label = stringResource(R.string.user_label),
                        value = draft.user,
                        placeholder = "backups",
                        onValueChange = { draft = draft.copy(user = it) },
                    )
                    FieldRow(
                        label = stringResource(R.string.backup_destination_folder),
                        value = draft.path,
                        placeholder = "/srv/backups",
                        onValueChange = { draft = draft.copy(path = it) },
                        showDivider = false,
                    )
                }
                if (state.destination.publicKey.isNotEmpty()) {
                    val target = candidates.firstOrNull { it.entry.host == draft.host }
                    GroupedSection(
                        header = stringResource(R.string.backup_destination_key),
                        note = stringResource(R.string.backup_destination_key_note),
                    ) {
                        GroupedRow(showDivider = target != null) {
                            Text(
                                state.destination.publicKey,
                                style = MaterialTheme.typography.bodySmall,
                                color = Gryonix.colors.secondaryLabel,
                            )
                        }
                        target?.let { server ->
                            ActionRow(
                                text = stringResource(
                                    R.string.backup_destination_authorize,
                                    server.name,
                                ),
                                enabled = !state.destinationBusy,
                                showDivider = false,
                                onClick = {
                                    backups.authorizeKey(server, state.destination.publicKey)
                                },
                            )
                        }
                    }
                }
                state.destinationKeyAuthorizedOn?.let { name ->
                    GroupedSection {
                        GroupedRow(showDivider = false) {
                            Text(
                                stringResource(R.string.backup_destination_authorized, name),
                                style = MaterialTheme.typography.bodyMedium,
                                color = Gryonix.colors.accent,
                            )
                        }
                    }
                }
            }

            BackupDestinationSettings.Kind.S3 -> GroupedSection(
                header = stringResource(R.string.backup_destination_bucket),
                note = stringResource(R.string.backup_destination_bucket_note),
            ) {
                FieldRow(
                    label = stringResource(R.string.backup_destination_bucket),
                    value = draft.bucket,
                    placeholder = "my-backups",
                    onValueChange = { draft = draft.copy(bucket = it) },
                )
                FieldRow(
                    label = stringResource(R.string.backup_destination_endpoint),
                    value = draft.host,
                    placeholder = "s3.eu-central-1.amazonaws.com",
                    onValueChange = { draft = draft.copy(host = it) },
                )
                FieldRow(
                    label = stringResource(R.string.backup_destination_prefix),
                    value = draft.path,
                    placeholder = "servers",
                    onValueChange = { draft = draft.copy(path = it) },
                )
                FieldRow(
                    label = stringResource(R.string.backup_destination_credentials),
                    value = secret,
                    onValueChange = { secret = it },
                    showDivider = false,
                    visualTransformation = PasswordVisualTransformation(),
                )
            }

            BackupDestinationSettings.Kind.NONE -> Unit
        }

        if (draft.kind != BackupDestinationSettings.Kind.NONE) {
            GroupedSection(footer = stringResource(R.string.backup_destination_keep_note)) {
                val everything = stringResource(R.string.backup_destination_keep_everything)
                StepperRow(
                    label = stringResource(R.string.backup_destination_keep),
                    value = draft.keep,
                    range = 0..90,
                    onChange = { draft = draft.copy(keep = it) },
                    showDivider = false,
                    format = { if (it == 0) everything else it.toString() },
                )
            }
        }

        GroupedSection(note = stringResource(R.string.backup_destination_check_note)) {
            state.destinationCheck?.let { result ->
                GroupedRow {
                    Text(
                        if (result.succeeded) {
                            stringResource(R.string.backup_destination_answered)
                        } else {
                            result.detail.ifEmpty { stringResource(R.string.backup_destination_silent) }
                        },
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (result.succeeded) Gryonix.colors.accent else Gryonix.colors.warning,
                    )
                }
            }
            state.destination.lastShipmentAt?.let { at ->
                GroupedRow {
                    Text(
                        stringResource(R.string.backup_destination_last_copy, android.text.format.DateUtils.getRelativeTimeSpanString(
                            at * 1000L,
                            System.currentTimeMillis(),
                            android.text.format.DateUtils.MINUTE_IN_MILLIS,
                        ).toString()),
                        style = MaterialTheme.typography.bodyMedium,
                        color = if (state.destination.lastShipmentSucceeded) {
                            Gryonix.colors.secondaryLabel
                        } else {
                            Gryonix.colors.warning
                        },
                    )
                }
                if (!state.destination.lastShipmentSucceeded && state.destination.lastError.isNotEmpty()) {
                    GroupedRow {
                        Text(
                            state.destination.lastError,
                            style = MaterialTheme.typography.bodySmall,
                            color = Gryonix.colors.warning,
                        )
                    }
                }
            }
            ActionRow(
                text = stringResource(R.string.backup_destination_check),
                enabled = draft.kind != BackupDestinationSettings.Kind.NONE && !state.destinationBusy,
                showDivider = false,
                onClick = { backups.checkDestination(deployment) },
            )
        }

        state.destinationError?.let { error ->
            GroupedSection {
                GroupedRow(showDivider = false) {
                    Text(
                        error,
                        style = MaterialTheme.typography.bodySmall,
                        color = Gryonix.colors.warning,
                    )
                }
            }
        }
    }
}
