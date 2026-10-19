package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.size
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSFullSheet
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.SheetAction
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.logs.ServiceLogsStatus
import com.skaymer.gryonixnexus.app.logs.ServiceLogsViewModel
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.servercontrol.Deployment

/** One service's container log */
@Composable
fun ServiceLogsDialog(
    deployment: Deployment,
    service: ManagedService,
    logs: ServiceLogsViewModel,
    onClose: () -> Unit,
) {
    val state by logs.state.collectAsState()
    val clipboard = LocalClipboardManager.current

    LaunchedEffect(deployment.id, service.id) { logs.start(deployment, service) }
    DisposableEffect(deployment.id, service.id) { onDispose { logs.close() } }

    IOSFullSheet(
        title = service.displayName,
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_done),
        action = SheetAction(
            title = stringResource(R.string.service_logs_copy),
            enabled = state.visible.isNotEmpty(),
            onSelect = { clipboard.setText(AnnotatedString(state.plainText())) },
        ),
    ) {
        Header(state.status, state.errorMessage, state.isLive, logs::reload)
        if (state.containers.size > 1) {
            ContainerFilter(state.containers, state.filter, logs::filter)
        }
        when {
            state.errorMessage != null -> Text(
                state.errorMessage!!,
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.danger,
                modifier = Modifier.padding(horizontal = Metrics.listInset),
            )
            state.saysThereIsNoOutput -> Text(
                stringResource(R.string.service_logs_no_output),
                style = MaterialTheme.typography.bodyMedium,
                color = Gryonix.colors.secondaryLabel,
                modifier = Modifier.padding(horizontal = Metrics.listInset),
            )
            state.visible.isEmpty() -> Row(
                Modifier.padding(horizontal = Metrics.listInset),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CircularProgressIndicator(
                    Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = Gryonix.colors.tertiaryLabel,
                )
                Text(
                    stringResource(R.string.containers_log_waiting),
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
            else -> Lines(state.visible, state.filter == null && state.containers.size > 1)
        }
    }
}
@Composable
private fun Header(
    status: ServiceLogsStatus,
    errorMessage: String?,
    isLive: Boolean,
    onReload: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().padding(start = Metrics.listInset, end = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            when {
                errorMessage != null -> stringResource(R.string.containers_log_failed)
                status == ServiceLogsStatus.CONNECTING -> stringResource(R.string.service_logs_connecting)
                status == ServiceLogsStatus.FOLLOWING -> stringResource(R.string.service_logs_live)
                isLive -> stringResource(R.string.service_logs_stream_ended)
                else -> stringResource(R.string.service_logs_snapshot)
            },
            style = MaterialTheme.typography.labelMedium,
            color = Gryonix.colors.secondaryLabel,
        )
        if (!isLive) {
            PlainButton(
                text = stringResource(R.string.service_logs_read_again),
                onClick = onReload,
                enabled = status != ServiceLogsStatus.CONNECTING,
            )
        }
    }
}

@Composable
private fun ContainerFilter(
    containers: List<String>,
    selected: String?,
    onPick: (String?) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box(Modifier.padding(start = Metrics.listInset - 8.dp)) {
        PlainButton(
            text = selected ?: stringResource(R.string.service_logs_all_containers),
            onClick = { open = true },
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            DropdownMenuItem(
                text = { Text(stringResource(R.string.service_logs_all_containers)) },
                onClick = { onPick(null); open = false },
            )
            containers.forEach { container ->
                DropdownMenuItem(
                    text = { Text(container) },
                    onClick = { onPick(container); open = false },
                )
            }
        }
    }
}

@Composable
private fun Lines(lines: List<com.skaymer.gryonixnexus.app.logs.ServiceLogLine>, tagged: Boolean) {
    val listState = rememberLazyListState()
    LaunchedEffect(lines.size) {
        if (lines.isNotEmpty()) listState.scrollToItem(lines.size - 1)
    }
    SelectionContainer {
        LazyColumn(Modifier.heightIn(max = 420.dp), state = listState) {
            itemsIndexed(lines) { _, line ->
                Column(Modifier.padding(vertical = 2.dp)) {
                    if (tagged) {
                        Text(
                            line.shortContainer,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Text(
                        line.text,
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                    )
                }
            }
        }
    }
}
