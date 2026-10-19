package com.skaymer.gryonixnexus.app.ui

import com.skaymer.gryonixnexus.app.storage.StorageAgentTasks
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.install.StorageStep
import com.skaymer.gryonixnexus.app.storage.StorageState
import com.skaymer.gryonixnexus.app.storage.StorageViewModel
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.AlertFields
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.catalog.storage.DiskHealth
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID

/** SMART for every disk, read as root */
@Composable
internal fun DiskHealthDialog(
    model: StorageViewModel,
    state: StorageState,
    server: Deployment,
    host: SSHHostID,
    account: StorageAccount,
    onClose: () -> Unit,
) {
    var sign by remember { mutableStateOf(account.sign) }
    var asked by remember { mutableStateOf(false) }
    var results by remember { mutableStateOf<List<DiskHealth>?>(null) }
    LaunchedEffect(state.running) {
        if (!state.running && asked) {
            asked = false
            state.lastOutput?.let { results = DiskHealth.parse(it) }
        }
    }
    val disks = state.hardware?.disks.orEmpty()
    IOSAlert(
        title = stringResource(R.string.health_title),
        message = state.failureText() ?: stringResource(R.string.health_about),
        onDismiss = onClose,
        actions = listOf(
            AlertAction(stringResource(R.string.containers_done), onSelect = onClose),
            AlertAction(
                stringResource(R.string.health_check),
                preferred = true,
                enabled = !state.running && disks.isNotEmpty(),
                onSelect = {
                    asked = true
                    sign.run(model, server, host, StorageAgentTasks.diskHealth(disks.map { it.path }))
                },
            ),
        ),
    ) {
        AlertFields {
            StorageSignInRows(account, sign) { sign = it }
        }
        results?.forEach { health ->
            val name = disks.firstOrNull { it.path == health.path }?.let { listOf(it.name, it.model).filter(String::isNotEmpty).joinToString(" · ") }
                ?: health.path
            Text(name, style = MaterialTheme.typography.bodyMedium, color = Gryonix.colors.label)
            Text(verdict(health), style = MaterialTheme.typography.bodySmall, color = tint(health.verdict))
            figures(health).takeIf { it.isNotEmpty() }?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = Gryonix.colors.secondaryLabel)
            }
        }
    }
}

@Composable
private fun verdict(health: DiskHealth): String = stringResource(
    when (health.verdict) {
        DiskHealth.Verdict.GOOD -> R.string.storage_array_healthy
        DiskHealth.Verdict.WATCH -> R.string.health_watch
        DiskHealth.Verdict.FAILING -> R.string.health_failing
        DiskHealth.Verdict.UNKNOWN -> R.string.health_unknown
    },
)

@Composable
private fun tint(verdict: DiskHealth.Verdict) = when (verdict) {
    DiskHealth.Verdict.GOOD -> Gryonix.colors.success
    DiskHealth.Verdict.WATCH -> Gryonix.colors.warning
    DiskHealth.Verdict.FAILING -> Gryonix.colors.danger
    DiskHealth.Verdict.UNKNOWN -> Gryonix.colors.secondaryLabel
}

@Composable
private fun figures(health: DiskHealth): String = listOfNotNull(
    health.temperature?.let { "$it °C" },
    health.powerOnHours?.let { stringResource(R.string.health_hours, it) },
    health.wornPercent?.let { stringResource(R.string.health_worn, it) },
    health.badSectors.takeIf { it > 0 }?.let { stringResource(R.string.health_bad_sectors, it) },
).joinToString(" · ")
