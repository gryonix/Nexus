package com.skaymer.gryonixnexus.app.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Extension
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.agentcontrol.AgentModOperations
import com.skaymer.gryonixnexus.app.servers.ModsViewModel
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.servercontrol.Deployment
import gryonixnexusd.v1.ModSlot
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The row that opens the uploaded files */
@Composable
fun ModsCard(callsThemPlugins: Boolean, onOpen: () -> Unit, showDivider: Boolean = true) {
    ValueRow(
        title = stringResource(if (callsThemPlugins) R.string.mods_plugins else R.string.mods),
        value = null,
        onClick = onOpen,
        showDivider = showDivider,
        leading = {
            Icon(Icons.Filled.Extension, contentDescription = null, modifier = Modifier.size(22.dp))
        },
    )
}

@Composable
fun ModsDialog(
    deployment: Deployment,
    flavour: String,
    mods: ModsViewModel,
    onClose: () -> Unit,
) {
    val state by mods.state.collectAsState()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var pickerError by remember(deployment.id) { mutableStateOf<String?>(null) }
    val callsThemPlugins = AgentModOperations.slot(flavour) == ModSlot.MOD_SLOT_PLUGINS

    LaunchedEffect(deployment.id) { mods.load(deployment) }

    val readFrom = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val name = DocumentFileName.of(context, uri)
        if (!name.endsWith(".jar", ignoreCase = true)) {
            pickerError = context.getString(R.string.mods_not_a_jar)
            return@rememberLauncherForActivityResult
        }
        scope.launch {
            val bytes = withContext(Dispatchers.IO) {
                runCatching { context.contentResolver.openInputStream(uri)?.use { it.readBytes() } }
                    .getOrNull()
            }
            if (bytes == null) {
                pickerError = context.getString(R.string.files_unreadable)
                return@launch
            }
            pickerError = null
            mods.upload(deployment, flavour, name, bytes)
        }
    }

    IOSSheet(
        title = stringResource(if (callsThemPlugins) R.string.mods_plugins_title else R.string.mods_title),
        onClose = onClose,
        closeLabel = stringResource(R.string.containers_done),
    ) {
        when {
            state.isLoading -> LoadingRow(stringResource(R.string.mods_loading))
            state.errorMessage == ModsViewModel.NO_AGENT ->
                GroupedSection { GroupedRow(showDivider = false) { Caption(stringResource(R.string.mods_no_agent)) } }
            else -> {
                GroupedSection(
                    header = stringResource(R.string.mods_header),
                    note = modsNote(callsThemPlugins),
                    footer = modsFreeSpace(state.freeBytes),
                ) {
                    if (state.files.isEmpty()) {
                        GroupedRow(showDivider = false) { Caption(stringResource(R.string.mods_empty)) }
                    } else {
                        state.files.forEachIndexed { index, file ->
                            GroupedRow(showDivider = index != state.files.lastIndex) {
                                Row(
                                    Modifier.fillMaxWidth(),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Column(Modifier.weight(1f)) {
                                        Text(
                                            file.name,
                                            style = MaterialTheme.typography.bodyMedium,
                                            color = Gryonix.colors.label,
                                        )
                                        Caption(ModsViewModel.human(file.size_bytes))
                                    }
                                    if (state.removing == file.name) {
                                        CircularProgressIndicator(
                                            Modifier.size(16.dp),
                                            strokeWidth = 2.dp,
                                            color = Gryonix.colors.tertiaryLabel,
                                        )
                                    } else {
                                        IconButton(
                                            onClick = { mods.remove(deployment, file) },
                                            enabled = !state.uploading,
                                        ) {
                                            Icon(
                                                Icons.Filled.Delete,
                                                contentDescription = stringResource(R.string.delete_server_confirm),
                                                modifier = Modifier.size(20.dp),
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    GroupedRow(showDivider = false) {
                        if (state.uploading) {
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                CircularProgressIndicator(
                                    Modifier.size(16.dp),
                                    strokeWidth = 2.dp,
                                    color = Gryonix.colors.tertiaryLabel,
                                )
                                Text(stringResource(R.string.mods_uploading), style = MaterialTheme.typography.bodyMedium)
                            }
                        } else {
                            Text(
                                stringResource(R.string.mods_upload),
                                style = MaterialTheme.typography.bodyMedium,
                                color = Gryonix.colors.accent,
                                modifier = Modifier.clickable { readFrom.launch(arrayOf("*/*")) },
                            )
                        }
                    }
                    (pickerError ?: state.errorMessage)?.let { message ->
                        GroupedRow(showDivider = false) {
                            Text(message, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun modsNote(callsThemPlugins: Boolean): String =
    stringResource(if (callsThemPlugins) R.string.mods_footer_plugins else R.string.mods_footer_mods)

@Composable
private fun modsFreeSpace(freeBytes: Long): String? =
    if (freeBytes <= 0) null else stringResource(R.string.mods_free, ModsViewModel.human(freeBytes))

@Composable
private fun LoadingRow(text: String) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CircularProgressIndicator(
            Modifier.size(16.dp),
            strokeWidth = 2.dp,
            color = Gryonix.colors.tertiaryLabel,
        )
        Caption(text)
    }
}

@Composable
private fun Caption(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = Gryonix.colors.secondaryLabel,
    )
}
