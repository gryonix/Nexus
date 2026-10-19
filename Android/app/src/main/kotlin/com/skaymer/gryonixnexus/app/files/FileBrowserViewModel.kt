package com.skaymer.gryonixnexus.app.files

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.RemoteFileBrowser
import com.skaymer.gryonixnexus.servercontrol.RemoteFileEntry
import com.skaymer.gryonixnexus.servercontrol.RemotePath
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class FileTransfer(val name: String, val isSending: Boolean)

data class DownloadedFile(val name: String, val bytes: ByteArray) {
    override fun equals(other: Any?): Boolean =
        this === other || (other is DownloadedFile && other.name == name && other.bytes === bytes)

    override fun hashCode(): Int = name.hashCode()
}

data class FileBrowserState(
    val host: SSHHostID? = null,
    val path: String = "",
    val entries: List<RemoteFileEntry> = emptyList(),
    val isLoading: Boolean = false,
    val transfer: FileTransfer? = null,
    val errorMessage: String? = null,
    /** Whether the server has answered about a directory at all */
    val hasAnswered: Boolean = false,
    val pendingDownload: DownloadedFile? = null,
) {
    val isAtRoot: Boolean get() = path == "/"

    val saysItIsEmpty: Boolean
        get() = hasAnswered && errorMessage == null && !isLoading && entries.isEmpty()
}

class FileBrowserViewModel(
    private val scope: CoroutineScope,
    private val browsers: suspend (Deployment) -> RemoteFileBrowser,
    private val startFolder: (Deployment) -> String? = { null },
    private val release: suspend (Deployment) -> Unit = {},
) {
    private val _state = MutableStateFlow(FileBrowserState())
    val state: StateFlow<FileBrowserState> = _state.asStateFlow()

    private var job: Job? = null

    /** First look: land where the control user lands */
    fun start(deployment: Deployment) {
        if (_state.value.hasAnswered || _state.value.isLoading) return
        open(deployment, deployment.servicesHost)
    }

    fun open(deployment: Deployment, host: SSHHostID) {
        if (host == _state.value.host) return
        job?.cancel()
        _state.value = FileBrowserState(host = host, isLoading = true)
        job = scope.launch {
            try {
                val browser = browsers(deployment)
                val home = browser.homeDirectory(host)
                val chosen = startFolder(deployment)?.trim()?.takeIf { it.isNotEmpty() && it != home }
                if (chosen != null) {
                    val listing = runCatching { browser.listDirectory(chosen, host) }.getOrNull()
                    if (listing != null) {
                        show(chosen, listing)
                        return@launch
                    }
                }
                show(home, browser.listDirectory(home, host))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                fail(deployment, failure)
            }
        }
    }

    /** The machine every call below is addressed to */
    private fun host(deployment: Deployment): SSHHostID =
        _state.value.host ?: deployment.servicesHost

    /** Re-read the directory on screen */
    fun refresh(deployment: Deployment) {
        val path = _state.value.path
        if (path.isEmpty()) {
            start(deployment)
            return
        }
        navigate(deployment, path)
    }

    /** Walk into a directory */
    fun open(deployment: Deployment, entry: RemoteFileEntry) {
        if (entry.kind != RemoteFileEntry.Kind.DIRECTORY) return
        navigate(deployment, entry.path)
    }

    /** Walk back out */
    fun goUp(deployment: Deployment) {
        val state = _state.value
        if (state.isAtRoot || state.path.isEmpty()) return
        navigate(deployment, RemotePath.parent(state.path))
    }

    /** Read one file down into memory and hand it over */
    fun download(
        deployment: Deployment,
        entry: RemoteFileEntry,
        onReady: (DownloadedFile) -> Unit = {},
    ) {
        if (entry.kind == RemoteFileEntry.Kind.DIRECTORY ||
            entry.kind == RemoteFileEntry.Kind.OTHER
        ) {
            return
        }
        scope.launch {
            _state.value = _state.value.copy(
                transfer = FileTransfer(entry.name, isSending = false),
                errorMessage = null,
            )
            val notice = OperationNotices.start(R.string.notice_downloading, entry.name,
                server = deployment.name, text = entry.path)
            try {
                val bytes = browsers(deployment)
                    .downloadFile(entry.path, host(deployment), TRANSFER_LIMIT_BYTES)
                val file = DownloadedFile(entry.name, bytes)
                _state.value = _state.value.copy(transfer = null, pendingDownload = file)
                onReady(file)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                fail(deployment, failure)
            } finally {
                notice.finish(OperationNotices.text(R.string.notice_done), _state.value.errorMessage)
            }
        }
    }

    fun clearDownload() {
        _state.value = _state.value.copy(pendingDownload = null)
    }

    fun upload(deployment: Deployment, name: String, bytes: ByteArray) {
        val directory = _state.value.path
        if (directory.isEmpty()) return
        scope.launch {
            _state.value = _state.value.copy(
                transfer = FileTransfer(name, isSending = true),
                errorMessage = null,
            )
            val notice = OperationNotices.start(R.string.notice_uploading, name,
                server = deployment.name, text = directory)
            try {
                val browser = browsers(deployment)
                val target = RemotePath.join(directory, RemotePath.fileName(name))
                browser.uploadFile(bytes, target, host(deployment))
                _state.value = _state.value.copy(transfer = null)
                show(directory, browser.listDirectory(directory, host(deployment)))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                fail(deployment, failure)
            } finally {
                notice.finish(OperationNotices.text(R.string.notice_done), _state.value.errorMessage)
            }
        }
    }

    fun delete(deployment: Deployment, entry: RemoteFileEntry) {
        val directory = _state.value.path
        scope.launch {
            _state.value = _state.value.copy(isLoading = true, errorMessage = null)
            try {
                val browser = browsers(deployment)
                browser.deleteFile(entry, host(deployment))
                show(directory, browser.listDirectory(directory, host(deployment)))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                fail(deployment, failure)
            }
        }
    }

    fun reset() {
        job?.cancel()
        job = null
        _state.value = FileBrowserState()
    }

    // MARK: - Internals

    /** Where you are changes only when the new place answered */
    private fun navigate(deployment: Deployment, path: String) {
        job?.cancel()
        job = scope.launch {
            _state.value = _state.value.copy(isLoading = true, errorMessage = null)
            try {
                val browser = browsers(deployment)
                show(path, browser.listDirectory(path, host(deployment)))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                fail(deployment, failure)
            }
        }
    }

    private fun show(path: String, entries: List<RemoteFileEntry>) {
        _state.value = _state.value.copy(
            path = path,
            entries = RemoteFileEntry.sorted(entries),
            isLoading = false,
            transfer = null,
            errorMessage = null,
            hasAnswered = true,
        )
    }

    private suspend fun fail(deployment: Deployment, failure: Exception) {
        release(deployment)
        _state.value = _state.value.copy(
            isLoading = false,
            transfer = null,
            errorMessage = failure.message ?: failure::class.simpleName.orEmpty(),
            hasAnswered = true,
        )
    }

    companion object {
        const val TRANSFER_LIMIT_BYTES: Long = 200L * 1024 * 1024

        fun canSend(sizeBytes: Long?): Boolean =
            sizeBytes == null || sizeBytes <= TRANSFER_LIMIT_BYTES

        /** What a row says about its size */
        fun sizeLabel(entry: RemoteFileEntry): String? =
            if (entry.kind == RemoteFileEntry.Kind.DIRECTORY) null else entry.size?.let(::bytes)

        private fun bytes(value: Long): String =
            com.skaymer.gryonixnexus.app.servers.MetricsFormat.bytes(value)
    }
}
