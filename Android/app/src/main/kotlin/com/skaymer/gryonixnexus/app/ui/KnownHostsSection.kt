package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.secrets.KnownHostsStore
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.servercontrol.KnownHostKey

@Composable
fun KnownHostsSection() {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val deployments by app.fleet.deployments.collectAsState()
    val known = remember { KnownHostsStore(app.secrets) }
    var revision by remember { mutableStateOf(0) }
    var forgetting by remember { mutableStateOf<KnownHostKey?>(null) }
    val rows = remember(deployments, revision) { known.rows(deployments) }

    GroupedSection(header = stringResource(R.string.known_hosts_title)) {
        if (rows.isEmpty()) {
            GroupedRow(showDivider = false) {
                Text(stringResource(R.string.known_hosts_empty), color = Gryonix.colors.secondaryLabel)
            }
        }
        rows.forEach { row -> KnownHostRow(row, showDivider = row != rows.last()) { forgetting = row } }
    }

    forgetting?.let { row ->
        ConfirmAlert(
            title = stringResource(R.string.known_hosts_forget_title),
            message = stringResource(R.string.known_hosts_forget_hint),
            confirm = stringResource(R.string.known_hosts_forget),
            destructive = true,
            onConfirm = {
                known.forget(row, deployments)
                forgetting = null
                revision++
            },
            onCancel = { forgetting = null },
        )
    }
}

@Composable
private fun KnownHostRow(row: KnownHostKey, showDivider: Boolean, onForget: () -> Unit) {
    val colors = Gryonix.colors
    GroupedRow(showDivider = showDivider) {
        Column(Modifier.weight(1f)) {
            Text("${row.serverName} · ${row.machineName}", style = MaterialTheme.typography.bodyLarge, color = colors.label)
            Text(row.endpoint, style = MaterialTheme.typography.bodySmall, color = colors.secondaryLabel)
            Text(row.keyType, style = MaterialTheme.typography.bodySmall, color = colors.secondaryLabel)
            Text(row.fingerprint, style = MaterialTheme.typography.bodySmall, color = colors.secondaryLabel,
                modifier = Modifier.padding(top = 2.dp))
            PlainButton(text = stringResource(R.string.known_hosts_forget), onClick = onForget, danger = true)
        }
    }
}
