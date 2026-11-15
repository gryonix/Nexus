package com.skaymer.gryonixnexus.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.GryonixApplication
import com.skaymer.gryonixnexus.app.ui.design.ActionRow
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.GroupedContentPadding
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.GroupedSpacing
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.servercontrol.AuthorizedKeysInstall
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.UserSshKey
import kotlinx.coroutines.launch
import kotlin.time.Duration.Companion.seconds

/** Pick servers, confirm, then append the key to authorized_keys */
@Composable
fun SshKeyInstallPage(key: UserSshKey, onClose: () -> Unit) {
    val app = LocalContext.current.applicationContext as GryonixApplication
    val servers by app.fleet.deployments.collectAsState()
    val chosen = remember { mutableStateMapOf<String, Boolean>() }
    val results = remember { mutableStateMapOf<String, String>() }
    var confirming by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val labels = InstallLabels(
        added = stringResource(R.string.ssh_keys_added),
        present = stringResource(R.string.ssh_keys_present),
        failed = stringResource(R.string.ssh_keys_failed),
    )
    androidx.activity.compose.BackHandler(onBack = onClose)
    val picked = servers.filter { chosen[it.id] == true }
    LazyColumn(
        Modifier.fillMaxSize().background(Gryonix.colors.groupedBackground),
        contentPadding = GroupedContentPadding,
        verticalArrangement = GroupedSpacing,
    ) {
        item {
            GroupedSection(footer = stringResource(R.string.ssh_keys_install_footer)) {
                servers.forEach { server -> ServerPickRow(server, chosen[server.id] == true, results[server.id],
                    server != servers.last()) { chosen[server.id] = !(chosen[server.id] ?: false) } }
            }
        }
        item {
            GroupedSection {
                ActionRow(stringResource(R.string.ssh_keys_install_action), { confirming = true },
                    enabled = picked.isNotEmpty(), showDivider = false)
            }
        }
    }
    if (confirming) {
        ConfirmAlert(
            title = stringResource(R.string.ssh_keys_install_confirm, key.name, picked.size),
            message = picked.joinToString("\n") { "${it.name} (${it.entry.user})" } + "\n\n" + key.fingerprint,
            confirm = stringResource(R.string.ssh_keys_install_action),
            onConfirm = {
                confirming = false
                scope.launch { picked.forEach { results[it.id] = install(app, it, key, labels) } }
            },
            onCancel = { confirming = false },
        )
    }
}

private class InstallLabels(val added: String, val present: String, val failed: String)

@Composable
private fun ServerPickRow(server: Deployment, picked: Boolean, result: String?, divider: Boolean, onToggle: () -> Unit) {
    GroupedRow(
        showDivider = divider,
        onClick = onToggle,
        trailing = {
            Icon(if (picked) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked, null,
                tint = Gryonix.colors.accent)
        },
    ) { RowLabel(server.name, result ?: "${server.entry.user}@${server.entry.host}") }
}

private suspend fun install(app: GryonixApplication, server: Deployment, key: UserSshKey, labels: InstallLabels): String {
    val command = AuthorizedKeysInstall.command(key.publicKey) ?: return labels.failed
    return runCatching {
        val result = app.sshRunner(server).run(command, SSHHostID.VPS, 20.seconds)
        when (AuthorizedKeysInstall.outcome(result)) {
            AuthorizedKeysInstall.Outcome.ADDED -> labels.added
            AuthorizedKeysInstall.Outcome.ALREADY_THERE -> labels.present
            AuthorizedKeysInstall.Outcome.FAILED -> labels.failed
        }
    }.getOrElse { it.message ?: labels.failed }
}
