package com.skaymer.gryonixnexus.app.ui

import androidx.compose.material.icons.filled.Upload
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.ArrowUpward
import android.widget.Toast
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.InsertDriveFile
import com.skaymer.gryonixnexus.app.ui.design.ConfirmAlert
import com.skaymer.gryonixnexus.app.ui.design.DisclosureChevron
import com.skaymer.gryonixnexus.app.ui.design.GroupedRow
import com.skaymer.gryonixnexus.app.ui.design.CheckRow
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.Metrics
import com.skaymer.gryonixnexus.app.ui.design.PlainButton
import com.skaymer.gryonixnexus.app.ui.design.Separator
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.files.FileBrowserViewModel
import com.skaymer.gryonixnexus.app.files.PosixMode
import com.skaymer.gryonixnexus.app.files.cancelSearch
import com.skaymer.gryonixnexus.app.files.clearSelection
import com.skaymer.gryonixnexus.app.files.jump
import com.skaymer.gryonixnexus.app.files.loadShortcuts
import com.skaymer.gryonixnexus.app.files.preview
import com.skaymer.gryonixnexus.app.files.search
import com.skaymer.gryonixnexus.app.files.toggleSelected
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.RemoteFileEntry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun FileBrowserSection(
    deployment: Deployment,
    files: FileBrowserViewModel,
) {
    val state by files.state.collectAsState()
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var deleting by remember(deployment.id) { mutableStateOf<RemoteFileEntry?>(null) }
    var saving by remember(deployment.id) { mutableStateOf<RemoteFileEntry?>(null) }
    var pickerError by remember(deployment.id) { mutableStateOf<String?>(null) }
    var acting by remember(deployment.id) { mutableStateOf<RemoteFileEntry?>(null) }
    var renaming by remember(deployment.id) { mutableStateOf<RemoteFileEntry?>(null) }
    var query by remember(deployment.id) { mutableStateOf("") }
    var selecting by remember(deployment.id) { mutableStateOf(false) }
    var batchRenaming by remember(deployment.id) { mutableStateOf(false) }
    var showShortcuts by remember(deployment.id) { mutableStateOf(false) }

    LaunchedEffect(deployment.id) {
        files.loadShortcuts(deployment)
        files.start(deployment)
    }
    DisposableEffect(deployment.id) { onDispose { files.reset() } }

    val saveTo = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("*/*"),
    ) { uri ->
        val entry = saving
        saving = null
        if (uri == null || entry == null) return@rememberLauncherForActivityResult
        files.download(deployment, entry) { file ->
            scope.launch(Dispatchers.IO) {
                val wrote = runCatching {
                    context.contentResolver.openOutputStream(uri)?.use { it.write(file.bytes) } != null
                }.getOrDefault(false)
                if (!wrote) withContext(Dispatchers.Main) { Toast.makeText(context, R.string.dkim_export_failed, Toast.LENGTH_LONG).show() }
                files.clearDownload()
            }
        }
    }

    val readFrom = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val name = DocumentFileName.of(context, uri)
        if (!FileBrowserViewModel.canSend(documentSize(context, uri))) {
            pickerError = context.getString(R.string.files_too_large, name)
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
            files.upload(deployment, name, bytes)
        }
    }

    Column(Modifier.fillMaxSize()) {
        if (deployment.isMultiHost) {
            GroupedSection(header = stringResource(R.string.terminal_pick_machine)) {
                deployment.nodes.forEach { candidate ->
                    CheckRow(
                        title = candidate.name.ifEmpty { candidate.endpoint.host },
                        subtitle = "${candidate.endpoint.user}@${candidate.endpoint.host}",
                        checked = candidate.sshHost == state.host,
                        onClick = { files.open(deployment, candidate.sshHost) },
                        showDivider = candidate != deployment.nodes.last(),
                    )
                }
            }
        }

        PathBar(
            path = state.path,
            isBusy = state.isLoading || state.transfer != null,
            canGoUp = !state.isAtRoot && state.path.isNotEmpty(),
            onUp = { files.goUp(deployment) },
            onRefresh = { files.refresh(deployment) },
            onUpload = { readFrom.launch(arrayOf("*/*")) },
        )
        BreadcrumbBar(state.path) { files.jump(deployment, it) }
        FileToolsBar(
            query = query,
            onQuery = {
                query = it
                if (it.isEmpty()) files.cancelSearch()
            },
            onSearch = { files.search(deployment, query) },
            isSearching = state.isSearching,
            onStop = {
                query = ""
                files.cancelSearch()
            },
            selecting = selecting,
            selectedCount = state.selection.size,
            onToggleSelecting = {
                selecting = !selecting
                files.clearSelection()
            },
            onBatchRename = { batchRenaming = true },
            onShortcuts = { showShortcuts = true },
        )

        state.transfer?.let { transfer ->
            Text(
                stringResource(
                    if (transfer.isSending) R.string.files_sending else R.string.files_receiving,
                    transfer.name,
                ),
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
        }

        (pickerError ?: state.errorMessage)?.let { message ->
            Text(
                message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
        }

        if (state.searchResults != null && state.searchResults!!.isEmpty()) {
            Text(
                stringResource(R.string.files_nothing_found),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(16.dp),
            )
        }

        if (state.saysItIsEmpty && state.searchResults == null) {
            Text(
                stringResource(R.string.files_empty),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(16.dp),
            )
        }

        if (state.isLoading && state.entries.isEmpty()) {
            Row(
                Modifier.fillMaxWidth().padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                CircularProgressIndicator(
                    Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                    color = Gryonix.colors.tertiaryLabel,
                )
                Text(
                    stringResource(R.string.files_reading),
                    style = MaterialTheme.typography.bodyMedium,
                    color = Gryonix.colors.secondaryLabel,
                )
            }
        }

        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp),
        ) {
            item {
                GroupedSection(dividerInset = 46.dp) {
                    val shown = state.shownEntries
                    shown.forEach { entry ->
                        EntryRow(
                            deployment = deployment,
                            files = files,
                            entry = entry,
                            selecting = selecting,
                            selected = entry.path in state.selection,
                            bookmarked = state.shortcuts.isBookmarked(entry.path),
                            onOpen = {
                                when {
                                    selecting -> files.toggleSelected(entry.path)
                                    entry.kind == RemoteFileEntry.Kind.DIRECTORY -> files.open(deployment, entry)
                                    else -> files.preview(deployment, entry)
                                }
                            },
                            onActions = { acting = entry },
                            showDivider = entry != shown.last(),
                        )
                    }
                }
            }
        }
    }

    FileBrowserDialogs(
        deployment = deployment,
        files = files,
        acting = acting,
        renaming = renaming,
        batchRenaming = batchRenaming,
        showShortcuts = showShortcuts,
        onActing = { acting = it },
        onRenaming = { renaming = it },
        onBatchRenaming = { batchRenaming = it },
        onShortcuts = { showShortcuts = it },
        onDownload = {
            saving = it
            saveTo.launch(it.name)
        },
        onDelete = { deleting = it },
    )

    deleting?.let { entry ->
        ConfirmAlert(
            title = stringResource(R.string.files_delete_confirm, entry.name),
            message = buildString {
                append(stringResource(R.string.files_delete_confirm_hint))
                if (entry.kind == RemoteFileEntry.Kind.DIRECTORY) {
                    append("\n")
                    append(stringResource(R.string.files_delete_dir_hint))
                }
            },
            confirm = stringResource(R.string.files_delete),
            cancel = stringResource(R.string.close),
            destructive = true,
            onConfirm = {
                deleting = null
                files.delete(deployment, entry)
            },
            onCancel = { deleting = null },
        )
    }
}

@Composable
private fun PathBar(
    path: String,
    isBusy: Boolean,
    canGoUp: Boolean,
    onUp: () -> Unit,
    onRefresh: () -> Unit,
    onUpload: () -> Unit,
) {
    val colors = Gryonix.colors
    Row(
        Modifier
            .fillMaxWidth()
            .background(colors.barBackground)
            .padding(start = Metrics.listInset, end = 4.dp, top = 4.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            path.ifEmpty { "…" },
            style = MaterialTheme.typography.bodyMedium,
            color = colors.label,
            maxLines = 1,
            overflow = TextOverflow.StartEllipsis,
            modifier = Modifier.weight(1f),
        )
        PathBarButton(Icons.Filled.ArrowUpward, stringResource(R.string.files_up), canGoUp && !isBusy, onUp)
        PathBarButton(Icons.Filled.Refresh, stringResource(R.string.files_refresh), !isBusy, onRefresh)
        PathBarButton(Icons.Filled.Upload, stringResource(R.string.files_upload), path.isNotEmpty() && !isBusy, onUpload)
    }
    Separator()
}

@Composable
private fun PathBarButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, enabled: Boolean, onClick: () -> Unit) {
    IconButton(onClick = onClick, enabled = enabled) {
        Icon(icon, contentDescription = label, tint = if (enabled) Gryonix.colors.accent else Gryonix.colors.tertiaryLabel)
    }
}

@Composable
private fun EntryRow(
    deployment: Deployment,
    files: FileBrowserViewModel,
    entry: RemoteFileEntry,
    selecting: Boolean,
    selected: Boolean,
    bookmarked: Boolean,
    onOpen: () -> Unit,
    onActions: () -> Unit,
    showDivider: Boolean = true,
) {
    val isDirectory = entry.kind == RemoteFileEntry.Kind.DIRECTORY
    val colors = Gryonix.colors
    GroupedRow(
        onClick = onOpen,
        onLongClick = onActions,
        showDivider = showDivider,
        leading = { FileIcon(deployment, files, entry) },
        trailing = {
            if (selecting) {
                Text(if (selected) "●" else "○", color = colors.accent)
            } else {
                if (bookmarked) Text("★", color = colors.accent)
                if (isDirectory) DisclosureChevron()
            }
        },
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                entry.name,
                style = MaterialTheme.typography.bodyLarge,
                color = colors.label,
                maxLines = 1,
                overflow = TextOverflow.MiddleEllipsis,
            )
            val details = listOfNotNull(
                PosixMode.format(entry.permissions),
                FileBrowserViewModel.sizeLabel(entry),
            )
            if (details.isNotEmpty()) {
                Text(
                    details.joinToString("   "),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.secondaryLabel,
                )
            }
        }
    }
}

private fun documentSize(context: Context, uri: Uri): Long? {
    context.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
        ?.use { cursor ->
            val column = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (column >= 0 && cursor.moveToFirst() && !cursor.isNull(column)) {
                return cursor.getLong(column)
            }
        }
    return null
}
