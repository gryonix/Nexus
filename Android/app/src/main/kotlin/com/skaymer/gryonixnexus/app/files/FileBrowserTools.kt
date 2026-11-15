package com.skaymer.gryonixnexus.app.files

import com.skaymer.gryonixnexus.servercontrol.BatchRename
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.FileSearch
import com.skaymer.gryonixnexus.servercontrol.FileShortcuts
import com.skaymer.gryonixnexus.servercontrol.FileTools
import com.skaymer.gryonixnexus.servercontrol.FilePreview
import com.skaymer.gryonixnexus.servercontrol.PreviewKind
import com.skaymer.gryonixnexus.servercontrol.RemoteFileEntry
import com.skaymer.gryonixnexus.servercontrol.RemotePath
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

class FilePreviewData(val name: String, val kind: PreviewKind, val bytes: ByteArray)

private const val BOOKMARKS_KEY = "files.bookmarks."
private const val RECENTS_KEY = "files.recents."

fun FileBrowserViewModel.loadShortcuts(deployment: Deployment) {
    val store = settings ?: return
    _state.value = _state.value.copy(
        shortcuts = FileShortcuts(
            bookmarks = store.stringList(BOOKMARKS_KEY + deployment.id).orEmpty(),
            recents = store.stringList(RECENTS_KEY + deployment.id).orEmpty(),
        ),
    )
}

private fun FileBrowserViewModel.updateShortcuts(deployment: Deployment, change: (FileShortcuts) -> FileShortcuts) {
    val next = change(_state.value.shortcuts)
    _state.value = _state.value.copy(shortcuts = next)
    settings?.setStringList(BOOKMARKS_KEY + deployment.id, next.bookmarks)
    settings?.setStringList(RECENTS_KEY + deployment.id, next.recents)
}

fun FileBrowserViewModel.toggleBookmark(deployment: Deployment, path: String) =
    updateShortcuts(deployment) { it.toggleBookmark(path) }

fun FileBrowserViewModel.noteOpened(deployment: Deployment, path: String) =
    updateShortcuts(deployment) { it.noteOpened(path) }

/** Jump to a breadcrumb or any folder on the way */
fun FileBrowserViewModel.jump(deployment: Deployment, path: String) {
    cancelSearch()
    if (path != _state.value.path) navigate(deployment, path)
}

fun FileBrowserViewModel.toggleSelected(path: String) {
    val current = _state.value.selection
    _state.value = _state.value.copy(selection = if (path in current) current - path else current + path)
}

fun FileBrowserViewModel.clearSelection() {
    _state.value = _state.value.copy(selection = emptySet())
}

fun FileBrowserViewModel.rename(deployment: Deployment, entry: RemoteFileEntry, newName: String) {
    val name = newName.trim()
    if (!FileTools.isValidName(name) || name == entry.name) return
    runChange(deployment) { browser, host ->
        val target = RemotePath.join(RemotePath.parent(entry.path), name)
        browser.renameFile(entry.path, target, host)
        updateShortcuts(deployment) { it.renamed(entry.path, target) }
    }
}

fun FileBrowserViewModel.batchPlan(find: String, replace: String): List<BatchRename.Change> {
    val state = _state.value
    val chosen = state.entries.filter { it.path in state.selection }.map { it.name }
    return BatchRename.plan(chosen, state.entries.map { it.name }.toSet(), find, replace)
}

fun FileBrowserViewModel.batchRename(deployment: Deployment, find: String, replace: String) {
    val changes = batchPlan(find, replace)
    if (changes.isEmpty()) return
    val directory = _state.value.path
    runChange(deployment) { browser, host ->
        for (change in changes) {
            val from = RemotePath.join(directory, change.oldName)
            val to = RemotePath.join(directory, change.newName)
            browser.renameFile(from, to, host)
            updateShortcuts(deployment) { it.renamed(from, to) }
        }
        clearSelection()
    }
}

private fun FileBrowserViewModel.runChange(
    deployment: Deployment,
    body: suspend (com.skaymer.gryonixnexus.servercontrol.RemoteFileBrowser, com.skaymer.gryonixnexus.servercontrol.SSHHostID) -> Unit,
) {
    val directory = _state.value.path
    scope.launch {
        _state.value = _state.value.copy(isLoading = true, errorMessage = null)
        try {
            val browser = browsers(deployment)
            val host = host(deployment)
            body(browser, host)
            show(directory, browser.listDirectory(directory, host))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            fail(deployment, failure)
        }
    }
}

/** Search the folder on screen by name, newest query wins */
fun FileBrowserViewModel.search(deployment: Deployment, query: String) {
    searchJob?.cancel()
    if (query.isBlank()) {
        cancelSearch()
        return
    }
    val root = _state.value.path
    _state.value = _state.value.copy(isSearching = true, errorMessage = null)
    searchJob = scope.launch {
        try {
            val found = browsers(deployment)
                .searchFiles(root, query, FileSearch.DEFAULT_LIMIT, host(deployment))
            _state.value = _state.value.copy(searchResults = found, isSearching = false)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            _state.value = _state.value.copy(isSearching = false, errorMessage = failure.message)
        }
    }
}

fun FileBrowserViewModel.cancelSearch() {
    searchJob?.cancel()
    searchJob = null
    _state.value = _state.value.copy(isSearching = false, searchResults = null)
}

/** Read a text or image file for the inline viewer */
fun FileBrowserViewModel.preview(deployment: Deployment, entry: RemoteFileEntry) {
    val kind = FilePreview.kind(entry)
    if (kind == PreviewKind.NONE) return
    scope.launch {
        _state.value = _state.value.copy(transfer = FileTransfer(entry.name, isSending = false), errorMessage = null)
        try {
            val bytes = browsers(deployment)
                .downloadFile(entry.path, host(deployment), PREVIEW_LIMIT_BYTES)
            noteOpened(deployment, entry.path)
            _state.value = _state.value.copy(transfer = null, preview = FilePreviewData(entry.name, kind, bytes))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            fail(deployment, failure)
        }
    }
}

fun FileBrowserViewModel.endPreview() {
    _state.value = _state.value.copy(preview = null)
}

suspend fun FileBrowserViewModel.thumbnail(deployment: Deployment, entry: RemoteFileEntry): ByteArray? {
    if (!FilePreview.canThumbnail(entry)) return null
    val key = "${deployment.id}${entry.path}${entry.size}${entry.modified}"
    thumbnails[key]?.let { return it }
    val bytes = try {
        browsers(deployment).downloadFile(entry.path, host(deployment), FilePreview.THUMBNAIL_LIMIT)
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (failure: Exception) {
        return null
    }
    if (thumbnails.size > THUMBNAIL_CACHE_SIZE) thumbnails.clear()
    thumbnails[key] = bytes
    return bytes
}

fun FileBrowserViewModel.openShortcut(deployment: Deployment, target: String) {
    cancelSearch()
    scope.launch {
        try {
            val browser = browsers(deployment)
            val host = host(deployment)
            val listing = runCatching { browser.listDirectory(target, host) }.getOrNull()
            if (listing != null) {
                show(target, listing)
                return@launch
            }
            val parent = RemotePath.parent(target)
            val siblings = browser.listDirectory(parent, host)
            show(parent, siblings)
            siblings.firstOrNull { it.path == target }?.let { preview(deployment, it) }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            fail(deployment, failure)
        }
    }
}

const val PREVIEW_LIMIT_BYTES: Long = 8L * 1024 * 1024
private const val THUMBNAIL_CACHE_SIZE = 200
