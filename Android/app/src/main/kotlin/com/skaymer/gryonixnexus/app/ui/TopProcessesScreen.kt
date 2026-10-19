package com.skaymer.gryonixnexus.app.ui

import android.text.format.Formatter
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.servers.TopProcessesState
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSegmentedControl
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ProcessRow
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.TopProcesses

/** What uses the most processor or memory on one machine */
@Composable
fun TopProcessesScreen(server: Deployment, host: SSHHostID) {
    val model = (LocalContext.current.applicationContext as GryonixApplication).processes
    val state by model.state.collectAsState()
    var friendly by rememberSaveable { mutableStateOf(true) }
    var byMemory by rememberSaveable { mutableStateOf(false) }
    DisposableEffect(server.id, host) {
        model.follow(server, host)
        onDispose { model.stop() }
    }
    val rows = TopProcesses.rows(state.samples, friendly, byMemory)
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item { ProcessOptions(friendly, byMemory, { friendly = it }, { byMemory = it }) }
        item { ProcessList(rows, state) }
    }
}

@Composable
private fun ProcessOptions(
    friendly: Boolean,
    byMemory: Boolean,
    onFriendly: (Boolean) -> Unit,
    onByMemory: (Boolean) -> Unit,
) {
    GroupedSection(footer = stringResource(R.string.processes_friendly_note)) {
        GroupedRow {
            IOSSegmentedControl(
                segments = listOf(false, true),
                selected = byMemory,
                modifier = Modifier.weight(1f),
                label = { stringResource(if (it) R.string.metrics_memory else R.string.metrics_cpu) },
                onSelect = onByMemory,
            )
        }
        ToggleRow(
            title = stringResource(R.string.processes_friendly),
            checked = friendly,
            onCheckedChange = onFriendly,
            showDivider = false,
        )
    }
}

@Composable
private fun ProcessList(rows: List<ProcessRow>, state: TopProcessesState) {
    val note = when {
        state.errorMessage != null -> state.errorMessage
        state.empty -> stringResource(R.string.processes_none)
        else -> stringResource(R.string.processes_every)
    }
    GroupedSection(footer = note) {
        if (!state.loaded) {
            GroupedRow(showDivider = false) {
                Text(stringResource(R.string.processes_reading), color = Gryonix.colors.secondaryLabel)
            }
        }
        rows.forEachIndexed { index, row -> ProcessLine(row, showDivider = index != rows.lastIndex) }
    }
}

@Composable
private fun ProcessLine(row: ProcessRow, showDivider: Boolean) {
    val context = LocalContext.current
    GroupedRow(showDivider = showDivider) {
        Column(Modifier.weight(1f)) {
            Text(if (row.count > 1) "${row.name} ×${row.count}" else row.name, style = MaterialTheme.typography.bodyLarge)
            if (row.detail.isNotEmpty()) {
                Text(
                    row.detail,
                    style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        Column(horizontalAlignment = Alignment.End) {
            Text("%.1f %%".format(row.cpu), style = MaterialTheme.typography.bodyLarge)
            Text(
                Formatter.formatShortFileSize(context, row.memoryKiB * 1024),
                style = MaterialTheme.typography.bodySmall,
                color = Gryonix.colors.secondaryLabel,
            )
        }
    }
}
