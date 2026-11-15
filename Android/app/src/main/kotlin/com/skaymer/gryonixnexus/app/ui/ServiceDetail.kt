package com.skaymer.gryonixnexus.app.ui

import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Notes
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.ArrowCircleDown
import androidx.compose.material.icons.outlined.Backup
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Hub
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.servers.BackupsViewModel
import com.skaymer.gryonixnexus.app.servers.HomeOnlyController
import com.skaymer.gryonixnexus.app.servers.ServiceControlViewModel
import com.skaymer.gryonixnexus.app.servers.UpdatesViewModel
import com.skaymer.gryonixnexus.app.shell.ServiceOwnNames
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.RowLabel
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow
import com.skaymer.gryonixnexus.app.ui.design.TileAction
import com.skaymer.gryonixnexus.app.ui.design.TileActionGroup
import com.skaymer.gryonixnexus.app.ui.design.ValueRow
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.UpdateSpec
import com.skaymer.gryonixnexus.catalog.services.PackagedAudioService
import com.skaymer.gryonixnexus.servercontrol.BackupEntry
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.ServicePowerAction
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What a service's own page needs beyond its row */
class ServiceTools(
    val backups: BackupsViewModel,
    val updates: UpdatesViewModel,
    val homeOnly: HomeOnlyController? = null,
    val reapply: ((Deployment, ManagedService) -> Unit)? = null,
    val audioOutputs: (suspend (Deployment) -> List<gryonixnexusd.v1.AudioOutput>)? = null,
    val odio: (suspend (Deployment, String, String, String) -> String)? = null,
    val names: ServiceOwnNames? = null,
    val rename: ((Deployment, ServiceID, String) -> Unit)? = null,
)

val LocalServiceTools = compositionLocalOf<ServiceTools?> { null }

/** A confirmation the page is waiting on */
private enum class ServiceAsk { STOP, RESTART, UPDATE }

/** Tiles, access, backups: what opens under a service */
@Composable
fun ServiceDetail(
    service: ManagedService,
    deployment: Deployment,
    services: ServiceControlViewModel,
    onLogs: () -> Unit,
    onRemove: () -> Unit,
    onAccess: (() -> Unit)?,
) {
    val tools = LocalServiceTools.current
    var asking by remember(service.id) { mutableStateOf<ServiceAsk?>(null) }
    var backingUp by remember(service.id) { mutableStateOf(false) }
    var restoring by remember(service.id) { mutableStateOf(false) }
    var listing by remember(service.id) { mutableStateOf(false) }
    var settingsOpen by remember(service.id) { mutableStateOf(false) }
    val actions = remember(service, deployment) { service.actions(deployment.serviceContext) }

    SpecTiles(
        serviceTiles(service, deployment, tools,
            onAsk = { asking = it }, onLogs = onLogs, onRemove = onRemove,
            onBackup = { backingUp = true }, onRestore = { restoring = true },
            onSettings = { settingsOpen = true },
            onStart = { services.power(deployment, service.id, ServicePowerAction.START) }),
        Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
    )
    if (tools != null && actions.backup != null) ServiceBackupsRow(service, deployment, tools.backups) { listing = true }

    asking?.let { ask -> ServiceConfirm(ask, service, deployment, services, tools) { asking = null } }
    if (backingUp && tools != null) BackupConfirmDialog(deployment, tools.backups, service) { backingUp = false }
    if (restoring && tools != null) RestorePickerDialog(deployment, tools.backups, service) { restoring = false }
    if (listing && tools != null) ServiceBackupsSheet(deployment, tools.backups, service) { listing = false }
    if (settingsOpen) {
        IOSSheet(title = serviceTitles(deployment.id)(service), onClose = { settingsOpen = false },
            closeLabel = stringResource(R.string.close)) {
            GroupedSection { ServiceSettingsRows(service, deployment, tools, onAccess) }
        }
    }
}

/** Every setting of one service, as rows */
@Composable
private fun ServiceSettingsRows(
    service: ManagedService,
    deployment: Deployment,
    tools: ServiceTools?,
    onAccess: (() -> Unit)?,
) {
    ServiceName(service, deployment, tools)
    onAccess?.let { ValueRow(stringResource(R.string.api_access_row), null, it, leading = { RowIcon(Icons.Outlined.Hub) }) }
    tools?.reapply?.let { reapply ->
        if (service.id == ServiceID.SHAIRPORT_SYNC && deployment.usesAgent) {
            AirPlaySpeakerRows(service, deployment, reapply, tools.audioOutputs)
        }
        if (service.id == ServiceID.UXPLAY && deployment.usesAgent) {
            AirPlayScreenRows(service, deployment, reapply)
        }
        if (service.id in PackagedAudioService.NAMED && deployment.usesAgent) {
            SpeakerNameRows(service, deployment, reapply)
        }
    }
    tools?.odio?.let { odio ->
        if (service.id == ServiceID.ODIO && deployment.usesAgent) AudioHubRow(deployment, odio)
    }
    SiteAddressRow(service, deployment, tools)
    HomeOnlyRow(service, deployment, tools?.homeOnly)
    InternalCertificateRow(service, deployment, tools?.homeOnly)
}

/** The name row, wired to the store */
@Composable
private fun ServiceName(service: ManagedService, deployment: Deployment, tools: ServiceTools?) {
    val rename = tools?.rename ?: return
    ServiceNameRow(
        service = service,
        current = tools.names?.title(service, deployment.id) ?: service.displayName,
        onRename = { rename(deployment, service.id, it) },
    )
}

private fun serviceTiles(
    service: ManagedService,
    deployment: Deployment,
    tools: ServiceTools?,
    onAsk: (ServiceAsk) -> Unit,
    onLogs: () -> Unit,
    onRemove: () -> Unit,
    onBackup: () -> Unit,
    onRestore: () -> Unit,
    onSettings: () -> Unit,
    onStart: () -> Unit,
): List<TileActionSpec> = buildList {
    val actions = service.actions(deployment.serviceContext)
    if (actions.start != null) add(TileActionSpec(R.string.service_start, Icons.Filled.PlayArrow, onStart))
    if (actions.stop != null) add(TileActionSpec(R.string.service_stop, Icons.Filled.Stop, { onAsk(ServiceAsk.STOP) }, danger = true))
    if (actions.restart != null) add(TileActionSpec(R.string.service_restart, Icons.Outlined.Refresh, { onAsk(ServiceAsk.RESTART) }))
    if (tools != null && service.updateSpec(deployment.serviceContext).flavour == UpdateSpec.Flavour.COMPOSE_PULL) {
        add(TileActionSpec(R.string.service_tile_update, Icons.Outlined.ArrowCircleDown, { onAsk(ServiceAsk.UPDATE) }))
    }
    add(TileActionSpec(R.string.tab_settings, Icons.Outlined.Settings, onSettings))
    if (actions.logs != null) add(TileActionSpec(R.string.service_tile_logs, Icons.AutoMirrored.Outlined.Notes, onLogs))
    if (tools != null && actions.backup != null) add(TileActionSpec(R.string.service_tile_backup, Icons.Outlined.Backup, onBackup))
    if (tools != null && actions.restore != null) {
        add(TileActionSpec(R.string.backups_restore, Icons.Outlined.History, onRestore, danger = true))
    }
    add(TileActionSpec(R.string.service_tile_remove, Icons.Filled.Delete, onRemove, danger = true))
}

/** A tile before its words are looked up */
private data class TileActionSpec(
    val title: Int,
    val icon: androidx.compose.ui.graphics.vector.ImageVector,
    val onClick: () -> Unit,
    val danger: Boolean = false,
)

@Composable
private fun SpecTiles(specs: List<TileActionSpec>, modifier: Modifier) {
    TileActionGroup(specs.map { TileAction(stringResource(it.title), it.icon, it.onClick, danger = it.danger) }, modifier)
}

@Composable
private fun RowIcon(icon: androidx.compose.ui.graphics.vector.ImageVector) {
    Icon(icon, null, tint = Gryonix.colors.accent, modifier = Modifier.size(22.dp))
}

/** Stop, restart and update ask first, as on iOS */
@Composable
private fun ServiceConfirm(
    ask: ServiceAsk,
    service: ManagedService,
    deployment: Deployment,
    services: ServiceControlViewModel,
    tools: ServiceTools?,
    onClose: () -> Unit,
) {
    val (title, note, verb) = when (ask) {
        ServiceAsk.STOP -> Triple(R.string.service_confirm_stop, R.string.service_confirm_stop_note, R.string.service_stop)
        ServiceAsk.RESTART -> Triple(R.string.service_confirm_restart, R.string.service_confirm_restart_note, R.string.service_restart)
        ServiceAsk.UPDATE -> Triple(R.string.service_confirm_update, R.string.service_confirm_update_note, R.string.service_tile_update)
    }
    ConfirmAlert(
        title = stringResource(title, tools?.names?.title(service, deployment.id) ?: service.displayName),
        message = stringResource(note),
        confirm = stringResource(verb),
        cancel = stringResource(R.string.containers_cancel),
        destructive = ask == ServiceAsk.STOP,
        onConfirm = {
            when (ask) {
                ServiceAsk.STOP -> services.power(deployment, service.id, ServicePowerAction.STOP)
                ServiceAsk.RESTART -> services.power(deployment, service.id, ServicePowerAction.RESTART)
                ServiceAsk.UPDATE -> tools?.updates?.run(deployment, service.id)
            }
            onClose()
        },
        onCancel = onClose,
    )
}

/** "Backups N ›", the count read once the page opens */
@Composable
private fun ServiceBackupsRow(service: ManagedService, deployment: Deployment, backups: BackupsViewModel, onOpen: () -> Unit) {
    val state by backups.state.collectAsState()
    LaunchedEffect(service.id) { if (state.services[service.id] == null) backups.list(deployment, service.id) }
    val count = state.services[service.id]?.entries?.size
    ValueRow(
        title = stringResource(R.string.backups),
        value = count?.toString(),
        onClick = onOpen,
        showDivider = false,
        leading = { RowIcon(Icons.Outlined.Storage) },
    )
}

/** This service's archives: save to the phone or delete */
@Composable
private fun ServiceBackupsSheet(deployment: Deployment, backups: BackupsViewModel, service: ManagedService, onClose: () -> Unit) {
    val state by backups.state.collectAsState()
    LaunchedEffect(service.id) { backups.list(deployment, service.id) }
    var deleting by remember(service.id) { mutableStateOf<BackupEntry?>(null) }
    val save = rememberSaveToPhone(deployment, backups, service.id)
    val listing = state.services[service.id]
    IOSSheet(title = serviceTitles(deployment.id)(service), onClose = onClose, closeLabel = stringResource(R.string.close)) {
        GroupedSection(header = stringResource(R.string.backups), footer = listing?.errorMessage) {
            when {
                listing == null || listing.isLoading -> NoteRow(stringResource(R.string.backups_loading))
                listing.saysThereAreNone -> NoteRow(stringResource(R.string.backups_none))
                else -> listing.entries.forEach { entry ->
                    BackupEntryRow(entry, entry != listing.entries.last(), onSave = { save(entry) }, onDelete = { deleting = entry })
                }
            }
        }
    }
    deleting?.let { entry ->
        ConfirmAlert(
            title = stringResource(R.string.backups_delete),
            message = deletionMessage(listOf(entry)),
            confirm = stringResource(R.string.backups_delete),
            cancel = stringResource(R.string.containers_cancel),
            destructive = true,
            onConfirm = {
                backups.delete(deployment, service.id, entry)
                deleting = null
            },
            onCancel = { deleting = null },
        )
    }
}

@Composable
private fun NoteRow(text: String) {
    GroupedRow(showDivider = false) {
        Text(text, style = MaterialTheme.typography.bodyMedium, color = Gryonix.colors.secondaryLabel)
    }
}

@Composable
private fun BackupEntryRow(entry: BackupEntry, showDivider: Boolean, onSave: () -> Unit, onDelete: () -> Unit) {
    val colors = Gryonix.colors
    GroupedRow(
        showDivider = showDivider,
        trailing = {
            if (entry.drive == null) {
                IconButton(onClick = onSave, modifier = Modifier.size(32.dp)) {
                    Icon(Icons.Outlined.FileDownload, stringResource(R.string.backups_save_to_device), tint = colors.accent,
                        modifier = Modifier.size(20.dp))
                }
            }
            IconButton(onClick = onDelete, modifier = Modifier.size(28.dp)) {
                Icon(Icons.Filled.Delete, stringResource(R.string.backups_delete), tint = colors.danger, modifier = Modifier.size(18.dp))
            }
        },
    ) {
        val context = LocalContext.current
        val date = entry.modifiedAtMillis?.let { dateText(context, it) } ?: entry.dateText
        val detail = stringResource(R.string.backups_entry_detail, entry.sizeText, date)
        val onDrive = entry.drive?.let { stringResource(R.string.drive_copy_on, it) }
        RowLabel(entry.displayName, listOfNotNull(detail, onDrive).joinToString(" · "))
    }
}

/** Downloads an archive and writes it where the user picks */
@Composable
private fun rememberSaveToPhone(deployment: Deployment, backups: BackupsViewModel, id: ServiceID): (BackupEntry) -> Unit {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var saving by remember(id) { mutableStateOf<BackupEntry?>(null) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/gzip")) { uri ->
        val entry = saving
        saving = null
        if (uri == null || entry == null) return@rememberLauncherForActivityResult
        backups.download(deployment, id, entry) { bytes, _ ->
            scope.launch(Dispatchers.IO) {
                val wrote = runCatching { context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) } != null }
                    .getOrDefault(false)
                if (!wrote) withContext(Dispatchers.Main) {
                    Toast.makeText(context, R.string.dkim_export_failed, Toast.LENGTH_LONG).show()
                }
            }
        }
    }
    return { entry ->
        saving = entry
        launcher.launch(entry.displayName)
    }
}
