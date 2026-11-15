package com.skaymer.gryonixnexus.app.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.InsertDriveFile
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.files.FileBrowserViewModel
import com.skaymer.gryonixnexus.app.files.FilePreviewData
import com.skaymer.gryonixnexus.app.files.batchPlan
import com.skaymer.gryonixnexus.app.files.batchRename
import com.skaymer.gryonixnexus.app.files.endPreview
import com.skaymer.gryonixnexus.app.files.openShortcut
import com.skaymer.gryonixnexus.app.files.rename
import com.skaymer.gryonixnexus.app.files.toggleBookmark
import com.skaymer.gryonixnexus.app.files.thumbnail
import com.skaymer.gryonixnexus.app.ui.design.ApplyPendingBar
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.IOSSheet
import com.skaymer.gryonixnexus.app.ui.design.AlertAction
import com.skaymer.gryonixnexus.app.ui.design.AlertFields
import com.skaymer.gryonixnexus.app.ui.design.FieldRow
import com.skaymer.gryonixnexus.app.ui.design.Gryonix
import com.skaymer.gryonixnexus.app.ui.design.IOSAlert
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.FilePreview
import com.skaymer.gryonixnexus.servercontrol.FileShortcuts
import com.skaymer.gryonixnexus.servercontrol.FileTools
import com.skaymer.gryonixnexus.servercontrol.PreviewKind
import com.skaymer.gryonixnexus.servercontrol.RemoteFileEntry
import com.skaymer.gryonixnexus.servercontrol.RemotePath

@Composable
fun BreadcrumbBar(path: String, onSelect: (String) -> Unit) {
    val crumbs = FileTools.breadcrumbs(path.ifEmpty { "/" })
    val scroll = rememberScrollState()
    LaunchedEffect(path) { scroll.scrollTo(scroll.maxValue) }
    Row(
        Modifier.fillMaxWidth().horizontalScroll(scroll).padding(horizontal = 16.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        crumbs.forEachIndexed { index, crumb ->
            if (index > 0) Text("›", color = Gryonix.colors.tertiaryLabel, modifier = Modifier.padding(horizontal = 6.dp))
            val last = index == crumbs.lastIndex
            Text(
                crumb.name,
                style = MaterialTheme.typography.bodyMedium,
                color = if (last) Gryonix.colors.label else Gryonix.colors.accent,
                modifier = Modifier.clickable(enabled = !last) { onSelect(crumb.path) },
            )
        }
    }
}

@Composable
fun SearchBar(query: String, onQuery: (String) -> Unit, onSubmit: () -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        FieldRow(
            label = stringResource(R.string.files_search_hint),
            value = query,
            onValueChange = onQuery,
            placeholder = stringResource(R.string.files_search_hint),
            showDivider = false,
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                imeAction = androidx.compose.ui.text.input.ImeAction.Search,
            ),
            keyboardActions = androidx.compose.foundation.text.KeyboardActions(onSearch = { onSubmit() }),
        )
    }
}

@Composable
fun FileIcon(deployment: Deployment, files: FileBrowserViewModel, entry: RemoteFileEntry) {
    val tint = Gryonix.colors.accent
    if (entry.kind == RemoteFileEntry.Kind.DIRECTORY) {
        Icon(Icons.Filled.Folder, null, tint = tint, modifier = Modifier.size(24.dp))
        return
    }
    var bitmap by remember(entry.path) { mutableStateOf<androidx.compose.ui.graphics.ImageBitmap?>(null) }
    LaunchedEffect(entry.path, entry.size) {
        if (!FilePreview.canThumbnail(entry)) return@LaunchedEffect
        val bytes = files.thumbnail(deployment, entry) ?: return@LaunchedEffect
        bitmap = decodeSampled(bytes, 96)
    }
    val loaded = bitmap
    if (loaded != null) {
        Image(loaded, null, contentScale = ContentScale.Crop,
            modifier = Modifier.size(24.dp).clip(RoundedCornerShape(4.dp)))
    } else {
        val image = FilePreview.kind(entry) == PreviewKind.IMAGE
        Icon(if (image) Icons.Filled.Image else Icons.Filled.InsertDriveFile, null, tint = tint,
            modifier = Modifier.size(24.dp))
    }
}

internal fun decodeSampled(bytes: ByteArray, target: Int): androidx.compose.ui.graphics.ImageBitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    var sample = 1
    while (bounds.outWidth / (sample * 2) >= target && bounds.outHeight / (sample * 2) >= target) sample *= 2
    val options = BitmapFactory.Options().apply { inSampleSize = sample }
    return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)?.asImageBitmap()
}

@Composable
fun PreviewDialog(preview: FilePreviewData, onClose: () -> Unit) {
    IOSAlert(
        title = preview.name,
        onDismiss = onClose,
        actions = listOf(AlertAction(stringResource(R.string.files_done), preferred = true, onSelect = onClose)),
    ) {
        if (preview.kind == PreviewKind.IMAGE) {
            val image = remember(preview) { decodeSampled(preview.bytes, 1024) }
            if (image != null) {
                Image(image, preview.name, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxWidth())
            }
        } else {
            val text = remember(preview) { String(preview.bytes, Charsets.UTF_8) }
            BasicText(
                text,
                style = MaterialTheme.typography.bodySmall.copy(color = Gryonix.colors.label),
                modifier = Modifier.heightIn(max = 360.dp).verticalScroll(rememberScrollState()),
            )
        }
    }
}

@Composable
fun BatchRenameDialog(files: FileBrowserViewModel, onRename: (String, String) -> Unit, onCancel: () -> Unit) {
    var find by remember { mutableStateOf("") }
    var replace by remember { mutableStateOf("") }
    files.state.value
    val plan = files.batchPlan(find, replace)
    IOSSheet(
        title = stringResource(R.string.files_rename_selected),
        onClose = onCancel,
        closeLabel = stringResource(R.string.close),
        bottomBar = {
            ApplyPendingBar(
                visible = plan.isNotEmpty(),
                apply = stringResource(R.string.files_rename),
                cancel = stringResource(R.string.pending_changes_cancel),
                onApply = { onRename(find, replace) },
                onRevert = { find = ""; replace = "" },
            )
        },
    ) {
        GroupedSection(
            footer = if (plan.isEmpty()) stringResource(R.string.files_no_changes)
            else plan.take(5).joinToString("\n") { "${it.oldName} → ${it.newName}" },
        ) {
            FieldRow(label = stringResource(R.string.files_find), value = find, onValueChange = { find = it })
            FieldRow(label = stringResource(R.string.files_replace_with), value = replace,
                onValueChange = { replace = it }, showDivider = false)
        }
    }
}

@Composable
fun ShortcutsDialog(shortcuts: FileShortcuts, onOpen: (String) -> Unit, onClose: () -> Unit) {
    IOSAlert(
        title = stringResource(R.string.files_bookmarks),
        onDismiss = onClose,
        actions = listOf(AlertAction(stringResource(R.string.files_done), preferred = true, onSelect = onClose)),
    ) {
        Column(Modifier.heightIn(max = 360.dp).verticalScroll(rememberScrollState())) {
            if (shortcuts.bookmarks.isEmpty() && shortcuts.recents.isEmpty()) {
                Text(stringResource(R.string.files_no_shortcuts), style = MaterialTheme.typography.bodySmall,
                    color = Gryonix.colors.secondaryLabel)
            }
            ShortcutList(stringResource(R.string.files_bookmarks), shortcuts.bookmarks, onOpen)
            ShortcutList(stringResource(R.string.files_recent), shortcuts.recents, onOpen)
        }
    }
}

@Composable
private fun ShortcutList(title: String, paths: List<String>, onOpen: (String) -> Unit) {
    if (paths.isEmpty()) return
    Text(title, style = MaterialTheme.typography.labelMedium, color = Gryonix.colors.secondaryLabel,
        modifier = Modifier.padding(top = 8.dp))
    paths.forEach { path ->
        Column(Modifier.fillMaxWidth().clickable { onOpen(path) }.padding(vertical = 6.dp)) {
            Text(RemotePath.name(path).ifEmpty { "/" }, style = MaterialTheme.typography.bodyMedium,
                color = Gryonix.colors.label)
            Text(path, style = MaterialTheme.typography.bodySmall, color = Gryonix.colors.secondaryLabel, maxLines = 1)
        }
    }
}

@Composable
fun EntryActionsDialog(
    entry: RemoteFileEntry,
    bookmarked: Boolean,
    onRename: () -> Unit,
    onBookmark: () -> Unit,
    onDownload: () -> Unit,
    onDelete: () -> Unit,
    onClose: () -> Unit,
) {
    val isDirectory = entry.kind == RemoteFileEntry.Kind.DIRECTORY
    val actions = buildList {
        if (!isDirectory) add(AlertAction(stringResource(R.string.files_download)) { onClose(); onDownload() })
        add(AlertAction(stringResource(R.string.files_rename)) { onClose(); onRename() })
        add(AlertAction(stringResource(if (bookmarked) R.string.files_remove_bookmark else R.string.files_add_bookmark)) {
            onClose(); onBookmark()
        })
        add(AlertAction(stringResource(R.string.files_delete), destructive = true) { onClose(); onDelete() })
        add(AlertAction(stringResource(R.string.close), onSelect = onClose))
    }
    IOSAlert(title = entry.name, onDismiss = onClose, actions = actions)
}

@Composable
fun FileToolsBar(
    query: String,
    onQuery: (String) -> Unit,
    onSearch: () -> Unit,
    isSearching: Boolean,
    onStop: () -> Unit,
    selecting: Boolean,
    selectedCount: Int,
    onToggleSelecting: () -> Unit,
    onBatchRename: () -> Unit,
    onShortcuts: () -> Unit,
) {
    SearchBar(query, onQuery, onSearch)
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ToolLink(stringResource(R.string.files_bookmarks), onShortcuts)
        ToolLink(stringResource(if (selecting) R.string.files_done_selecting else R.string.files_select), onToggleSelecting)
        if (selecting && selectedCount > 0) ToolLink(stringResource(R.string.files_rename_selected), onBatchRename)
        if (isSearching) ToolLink(stringResource(R.string.files_stop), onStop)
    }
}

@Composable
private fun ToolLink(text: String, onClick: () -> Unit) {
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        color = Gryonix.colors.accent,
        modifier = Modifier.clickable(onClick = onClick).padding(end = 18.dp, top = 4.dp, bottom = 4.dp),
    )
}

@Composable
fun FileBrowserDialogs(
    deployment: Deployment,
    files: FileBrowserViewModel,
    acting: RemoteFileEntry?,
    renaming: RemoteFileEntry?,
    batchRenaming: Boolean,
    showShortcuts: Boolean,
    onActing: (RemoteFileEntry?) -> Unit,
    onRenaming: (RemoteFileEntry?) -> Unit,
    onBatchRenaming: (Boolean) -> Unit,
    onShortcuts: (Boolean) -> Unit,
    onDownload: (RemoteFileEntry) -> Unit,
    onDelete: (RemoteFileEntry) -> Unit,
) {
    val state by files.state.collectAsState()
    acting?.let { entry ->
        EntryActionsDialog(
            entry = entry,
            bookmarked = state.shortcuts.isBookmarked(entry.path),
            onRename = { onRenaming(entry) },
            onBookmark = { files.toggleBookmark(deployment, entry.path) },
            onDownload = { onDownload(entry) },
            onDelete = { onDelete(entry) },
            onClose = { onActing(null) },
        )
    }
    renaming?.let { entry ->
        NameEditSheet(
            title = stringResource(R.string.files_rename),
            label = stringResource(R.string.files_name),
            initial = entry.name,
            valid = { FileTools.isValidName(it.trim()) },
            onSave = { files.rename(deployment, entry, it) },
            onClose = { onRenaming(null) },
        )
    }
    if (batchRenaming) {
        BatchRenameDialog(files, onRename = { find, replace ->
            onBatchRenaming(false)
            files.batchRename(deployment, find, replace)
        }, onCancel = { onBatchRenaming(false) })
    }
    if (showShortcuts) {
        ShortcutsDialog(state.shortcuts, onOpen = {
            onShortcuts(false)
            files.openShortcut(deployment, it)
        }, onClose = { onShortcuts(false) })
    }
    state.preview?.let { PreviewDialog(it, onClose = files::endPreview) }
}
