package com.skaymer.gryonixnexus.app.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material.icons.filled.QrCode2
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.DeploymentTransferService
import com.skaymer.gryonixnexus.app.servers.QuickTransferReceiveState
import com.skaymer.gryonixnexus.app.servers.QuickTransferSendState
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.ProminentButton
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** The sending side: QR code, the question, the dots */
@Composable
fun QuickTransferSendSheet(deployments: List<Deployment>, transfer: DeploymentTransferService, onClose: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val state = remember {
        QuickTransferSendState(context, deployments, { runCatching { transfer.encode(transfer.exportFor(it)) }.getOrNull() }, scope)
    }
    var bluetooth by remember { mutableStateOf(false) }
    BluetoothAccess(sending = true) { granted ->
        bluetooth = granted
        state.start(granted)
    }
    DisposableEffect(Unit) { onDispose { state.stop() } }
    val finished = state.phase is QuickTransferSendState.Phase.Sent
    IOSSheet(
        title = stringResource(R.string.quick_transfer_send),
        onClose = onClose,
        closeLabel = stringResource(if (finished) R.string.group_done else R.string.group_cancel),
    ) {
        QuickTransferColumn { SendStage(state, bluetooth, onClose) }
    }
}

@Composable
private fun SendStage(state: QuickTransferSendState, bluetooth: Boolean, onClose: () -> Unit) {
    when (val phase = state.phase) {
        QuickTransferSendState.Phase.Starting -> Waiting(stringResource(R.string.quick_transfer_preparing))
        QuickTransferSendState.Phase.Showing, is QuickTransferSendState.Phase.Asking -> {
            val modules = remember(state.ticket) { state.ticket?.let { QuickTransferModules.grid(it.text) } ?: emptyList() }
            val asking = phase as? QuickTransferSendState.Phase.Asking
            QuickTransferQrCode(modules, scattered = asking != null, label = stringResource(R.string.quick_transfer_qr_label))
            if (asking == null) {
                Hint(stringResource(R.string.quick_transfer_scan_title), stringResource(R.string.quick_transfer_scan_detail))
            } else {
                Asking(asking, onAllow = state::allow, onDecline = { state.decline(bluetooth) })
            }
        }
        is QuickTransferSendState.Phase.Sending -> {
            QuickTransferDots(Icons.Filled.PhoneAndroid, Icons.Filled.PhoneAndroid)
            Text(stringResource(R.string.quick_transfer_sending, phase.device), color = Gryonix.colors.secondaryLabel)
        }
        is QuickTransferSendState.Phase.Sent -> {
            Icon(Icons.Filled.CheckCircle, null, Modifier.size(72.dp), tint = Gryonix.colors.success)
            Text(stringResource(R.string.quick_transfer_sent, phase.device), style = MaterialTheme.typography.titleMedium)
            ProminentButton(stringResource(R.string.group_done), onClick = onClose)
        }
        is QuickTransferSendState.Phase.Failed -> Failed(phase.message) { state.start(bluetooth) }
    }
}

@Composable
private fun Asking(asking: QuickTransferSendState.Phase.Asking, onAllow: () -> Unit, onDecline: () -> Unit) {
    QuickTransferCodeBadge(asking.code)
    Hint(stringResource(R.string.quick_transfer_asking, asking.device), stringResource(R.string.quick_transfer_asking_detail))
    Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        PlainButton(stringResource(R.string.quick_transfer_decline), onClick = onDecline, danger = true)
        ProminentButton(stringResource(R.string.quick_transfer_allow), onClick = onAllow, modifier = Modifier.weight(1f))
    }
}

/** The server chooser, then the sending sheet */
@Composable
fun QuickTransferSendDialogs(
    deployments: List<Deployment>,
    transfer: DeploymentTransferService,
    choosing: Boolean,
    sending: List<Deployment>?,
    onChosen: (List<Deployment>) -> Unit,
    onClose: () -> Unit,
) {
    if (choosing) {
        ExportSeveralDialog(
            deployments = deployments,
            onDismiss = onClose,
            onChosen = onChosen,
            title = stringResource(R.string.quick_transfer_send),
            actionTitle = stringResource(R.string.quick_transfer_next),
        )
    }
    sending?.let { chosen -> QuickTransferSendSheet(chosen, transfer, onClose) }
}

/** The receiving side: camera, the code, the arrival */
@Composable
fun QuickTransferReceiveSheet(deliver: (List<String>) -> List<String>, onClose: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val state = remember { QuickTransferReceiveState(context, deliver, scope) }
    var bluetooth by remember { mutableStateOf(false) }
    BluetoothAccess(sending = false) { bluetooth = it }
    DisposableEffect(Unit) { onDispose { state.stop() } }
    val finished = state.phase is QuickTransferReceiveState.Phase.Received
    IOSSheet(
        title = stringResource(R.string.quick_transfer_receive),
        onClose = onClose,
        closeLabel = stringResource(if (finished) R.string.group_done else R.string.group_cancel),
    ) {
        QuickTransferColumn { ReceiveStage(state, bluetooth, onClose) }
    }
}

@Composable
private fun ReceiveStage(state: QuickTransferReceiveState, bluetooth: Boolean, onClose: () -> Unit) {
    when (val phase = state.phase) {
        QuickTransferReceiveState.Phase.Scanning -> {
            QuickTransferScanner { state.scanned(it, bluetooth) }
            Hint(stringResource(R.string.quick_transfer_point_title), stringResource(R.string.quick_transfer_point_detail))
        }
        QuickTransferReceiveState.Phase.Connecting -> Travel(stringResource(R.string.quick_transfer_connecting))
        is QuickTransferReceiveState.Phase.Confirming -> {
            QuickTransferCodeBadge(phase.code)
            Hint(stringResource(R.string.quick_transfer_check_title), stringResource(R.string.quick_transfer_check_detail))
        }
        QuickTransferReceiveState.Phase.Receiving -> Travel(stringResource(R.string.quick_transfer_receiving))
        is QuickTransferReceiveState.Phase.Received -> {
            QuickTransferArrival(phase.names)
            ProminentButton(stringResource(R.string.group_done), onClick = onClose)
        }
        is QuickTransferReceiveState.Phase.Failed -> Failed(phase.message, state::retry)
    }
}

@Composable
private fun QuickTransferColumn(content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(20.dp),
        content = content,
    )
}

@Composable
private fun Travel(caption: String) {
    QuickTransferDots(Icons.Filled.QrCode2, Icons.Filled.PhoneAndroid)
    Text(caption, color = Gryonix.colors.secondaryLabel)
}

@Composable
private fun Waiting(caption: String) {
    CircularProgressIndicator(Modifier.padding(vertical = 100.dp), color = Gryonix.colors.accent)
    Text(caption, color = Gryonix.colors.secondaryLabel)
}

@Composable
private fun Hint(title: String, detail: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium, color = Gryonix.colors.label, textAlign = TextAlign.Center)
        Text(detail, color = Gryonix.colors.secondaryLabel, textAlign = TextAlign.Center)
    }
}

@Composable
private fun Failed(message: String, onRetry: () -> Unit) {
    Icon(Icons.Filled.Warning, null, Modifier.size(56.dp), tint = Gryonix.colors.warning)
    Text(message, color = Gryonix.colors.label, textAlign = TextAlign.Center)
    ProminentButton(stringResource(R.string.quick_transfer_try_again), onClick = onRetry)
}

/** Asks for Bluetooth once and reports the answer */
@Composable
private fun BluetoothAccess(sending: Boolean, onReady: (Boolean) -> Unit) {
    val context = LocalContext.current
    val needed = remember(sending) { bluetoothPermissions(sending) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
        onReady(results.values.all { it })
    }
    LaunchedEffect(Unit) {
        if (needed.all { granted(context, it) }) onReady(true) else launcher.launch(needed.toTypedArray())
    }
}

private fun bluetoothPermissions(sending: Boolean): List<String> = when {
    Build.VERSION.SDK_INT >= 31 -> listOf(
        Manifest.permission.BLUETOOTH_CONNECT,
        if (sending) Manifest.permission.BLUETOOTH_ADVERTISE else Manifest.permission.BLUETOOTH_SCAN,
    )
    sending -> emptyList()
    else -> listOf(Manifest.permission.ACCESS_FINE_LOCATION)
}

private fun granted(context: Context, permission: String) =
    ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
