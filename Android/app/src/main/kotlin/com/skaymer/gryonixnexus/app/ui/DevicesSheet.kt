package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import com.skaymer.gryonixnexus.app.security.LocalDeviceGate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.devices.DevicesState
import com.skaymer.gryonixnexus.app.devices.DevicesViewModel
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.LoadingRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.servercontrol.Deployment
import gryonixnexusd.v1.Device
import java.text.DateFormat
import java.util.Date

@Composable
fun DevicesCard(onOpen: () -> Unit, showDivider: Boolean = true) {
    ValueRow(
        title = stringResource(R.string.devices_title),
        value = null,
        onClick = onOpen,
        showDivider = showDivider,
        leading = {
            Icon(
                Icons.Filled.PhoneAndroid,
                contentDescription = null,
                modifier = Modifier.size(22.dp),
            )
        },
    )
}

@Composable
fun DevicesDialog(deployment: Deployment, devices: DevicesViewModel, onClose: () -> Unit) {
    val state by devices.state.collectAsState()
    var confirming by remember { mutableStateOf<Device?>(null) }

    LaunchedEffect(deployment.id) { devices.load(deployment) }
    DisposableEffect(deployment.id) { onDispose { devices.reset() } }

    IOSSheet(
        title = stringResource(R.string.devices_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_done),
    ) {
        when {
            state.isLoading -> LoadingRow()
            state.needsSignIn -> GroupedSection(
                footer = stringResource(R.string.devices_signed_out_footer),
            ) {
                WarningRow(stringResource(R.string.devices_signed_out))
            }
            state.failure == DevicesViewModel.UNIDENTIFIED_MARKER ->
                WarningSection(stringResource(R.string.devices_unidentified))
            state.failure != null -> WarningSection(state.failure!!)
            else -> PairedDevices(deployment, devices, state) { confirming = it }
        }
        if (state.needsSignIn) SignInAgainSection(deployment, devices, state)
        state.revokeError?.let { WarningSection(it, small = true) }
    }

    confirming?.let { device ->
        ConfirmAlert(
            title = stringResource(R.string.devices_remove_title),
            message = stringResource(
                R.string.devices_remove_message,
                device.label.ifEmpty { stringResource(R.string.devices_this_device) },
            ),
            confirm = stringResource(R.string.devices_remove),
            destructive = true,
            onConfirm = {
                devices.revoke(deployment, device)
                confirming = null
            },
            onCancel = { confirming = null },
        )
    }
}

@Composable
private fun WarningRow(text: String, small: Boolean = false) {
    GroupedRow(showDivider = false) {
        Text(
            text,
            style = if (small) MaterialTheme.typography.bodySmall else MaterialTheme.typography.bodyMedium,
            color = Gryonix.colors.warning,
        )
    }
}

@Composable
private fun WarningSection(text: String, small: Boolean = false) {
    GroupedSection { WarningRow(text, small) }
}

@Composable
private fun PairedDevices(
    deployment: Deployment,
    devices: DevicesViewModel,
    state: DevicesState,
    onRemove: (Device) -> Unit,
) {
    GroupedSection(
        header = stringResource(R.string.devices_paired_header),
        note = stringResource(R.string.devices_paired_footer),
    ) {
        if (state.devices.isEmpty()) {
            GroupedRow(showDivider = false) {
                Text(
                    stringResource(R.string.devices_none),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
        }
        state.devices.forEachIndexed { index, device ->
            DeviceRow(
                device = device,
                isThisDevice = devices.isThisDevice(device),
                isRevoking = state.revoking == device.id,
                showDivider = index < state.devices.lastIndex,
                onRemove = { onRemove(device) },
            )
        }
    }
    SessionTermSection(deployment, devices, state.autoLogoutMonths, state.savingPolicy)
    state.policyError?.let { WarningSection(it, small = true) }
}

@Composable
private fun SignInAgainSection(
    deployment: Deployment,
    devices: DevicesViewModel,
    state: DevicesState,
) {
    val gate = LocalDeviceGate.current
    val signInReason = stringResource(R.string.devices_sign_in_reason)
    GroupedSection {
        GroupedRow(showDivider = false) {
            if (state.signingIn) CircularProgressIndicator(Modifier.size(18.dp))
            else PlainButton(text = stringResource(R.string.devices_sign_in_again), onClick = {
                devices.signInAgain(deployment) {
                    withContext(Dispatchers.Main) { gate.confirm(signInReason) }
                }
            })
        }
        state.signInError?.let { Text(it, color = Gryonix.colors.warning) }
    }
}

@Composable
private fun DeviceRow(
    device: Device,
    isThisDevice: Boolean,
    isRevoking: Boolean,
    showDivider: Boolean,
    onRemove: () -> Unit,
) {
    GroupedRow(
        showDivider = showDivider,
        trailing = {
            if (isRevoking) {
                CircularProgressIndicator(
                    Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = Gryonix.colors.tertiaryLabel,
                )
            } else {
                PlainButton(
                    text = stringResource(R.string.devices_remove),
                    onClick = onRemove,
                    danger = true,
                )
            }
        },
    ) {
        Column {
            Text(
                device.label.ifEmpty { stringResource(R.string.devices_unnamed) },
                style = MaterialTheme.typography.bodyLarge,
                color = Gryonix.colors.label,
            )
            Text(
                buildString {
                    if (isThisDevice) {
                        append(stringResource(R.string.devices_this_device))
                        append(" · ")
                    }
                    append(pairedAt(device.paired_at))
                },
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.secondaryLabel,
            )
        }
    }
}

/** How long a device stays signed in */
@Composable
private fun SessionTermSection(
    deployment: Deployment,
    devices: DevicesViewModel,
    months: Int,
    saving: Boolean,
) {
    GroupedSection(
        header = stringResource(R.string.devices_term_header),
        note = stringResource(R.string.devices_term_footer),
    ) {
        DevicesViewModel.OFFERED_MONTHS.forEachIndexed { index, option ->
            GroupedRow(
                onClick = { if (!saving) devices.setAutoLogout(deployment, option) },
                showDivider = index < DevicesViewModel.OFFERED_MONTHS.lastIndex,
                trailing = {
                    if (option == months) {
                        Text("✓", color = Gryonix.colors.accent)
                    }
                },
            ) {
                Text(
                    if (option == 0) {
                        stringResource(R.string.devices_term_never)
                    } else {
                        stringResource(R.string.devices_term_months, option)
                    },
                    style = MaterialTheme.typography.bodyLarge,
                    color = Gryonix.colors.label,
                )
            }
        }
    }
}

/** The date the server recorded, in the reader's own format */
private fun pairedAt(seconds: Long): String =
    if (seconds <= 0) {
        ""
    } else {
        DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(seconds * 1000))
    }
