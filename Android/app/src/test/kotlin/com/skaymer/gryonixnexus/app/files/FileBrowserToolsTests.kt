package com.skaymer.gryonixnexus.app.files

import com.skaymer.gryonixnexus.app.shell.InMemorySettingsStore
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.RemoteFileBrowser
import com.skaymer.gryonixnexus.servercontrol.RemoteFileEntry
import com.skaymer.gryonixnexus.servercontrol.RemotePath
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class FileBrowserToolsTests {
    private val server = Deployment(
        id = "S-1", name = "middle", topology = Topology.SINGLE_HOST, domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"), services = emptySet(),
    )

    private class Disk(val names: MutableList<String>) : RemoteFileBrowser {
        val renames = mutableListOf<Pair<String, String>>()

        override suspend fun homeDirectory(host: SSHHostID) = "/data"

        override suspend fun listDirectory(path: String, host: SSHHostID): List<RemoteFileEntry> =
            if (path == "/data") names.map {
                RemoteFileEntry(it, RemotePath.join(path, it), RemoteFileEntry.Kind.FILE, 10)
            } else emptyList()

        override suspend fun downloadFile(path: String, host: SSHHostID, maxBytes: Long) = ByteArray(0)
        override suspend fun uploadFile(data: ByteArray, path: String, host: SSHHostID) = Unit
        override suspend fun deleteFile(entry: RemoteFileEntry, host: SSHHostID) = Unit

        override suspend fun renameFile(oldPath: String, newPath: String, host: SSHHostID) {
            renames += oldPath to newPath
            names[names.indexOf(RemotePath.name(oldPath))] = RemotePath.name(newPath)
        }
    }

    @Test
    fun `renaming asks the host and relists`() = runTest(StandardTestDispatcher()) {
        val disk = Disk(mutableListOf("a.txt"))
        val files = FileBrowserViewModel(this, { disk }, settings = InMemorySettingsStore())
        files.start(server)
        runCurrent()
        files.rename(server, files.state.value.entries.single(), "b.txt")
        runCurrent()
        assertEquals(listOf("/data/a.txt" to "/data/b.txt"), disk.renames)
        assertEquals(listOf("b.txt"), files.state.value.entries.map { it.name })
    }

    @Test
    fun `a batch rename renames the selected and clears the selection`() = runTest(StandardTestDispatcher()) {
        val disk = Disk(mutableListOf("a_old", "b_old", "c_old"))
        val files = FileBrowserViewModel(this, { disk }, settings = InMemorySettingsStore())
        files.start(server)
        runCurrent()
        files.toggleSelected("/data/a_old")
        files.toggleSelected("/data/b_old")
        files.batchRename(server, "_old", "_new")
        runCurrent()
        assertEquals(setOf("a_new", "b_new", "c_old"), files.state.value.entries.map { it.name }.toSet())
        assertEquals(emptySet(), files.state.value.selection)
    }

    @Test
    fun `search shows results and cancel clears them`() = runTest(StandardTestDispatcher()) {
        val disk = Disk(mutableListOf("report.txt", "notes.txt"))
        val files = FileBrowserViewModel(this, { disk }, settings = InMemorySettingsStore())
        files.start(server)
        runCurrent()
        files.search(server, "report")
        runCurrent()
        assertEquals(listOf("report.txt"), files.state.value.shownEntries.map { it.name })
        files.cancelSearch()
        assertNull(files.state.value.searchResults)
        assertEquals(2, files.state.value.shownEntries.size)
    }

    @Test
    fun `bookmarks and recents are kept per server in the settings`() = runTest(StandardTestDispatcher()) {
        val settings = InMemorySettingsStore()
        val files = FileBrowserViewModel(this, { Disk(mutableListOf()) }, settings = settings)
        files.toggleBookmark(server, "/data/x")
        files.noteOpened(server, "/data/y")
        val again = FileBrowserViewModel(this, { Disk(mutableListOf()) }, settings = settings)
        again.loadShortcuts(server)
        assertEquals(listOf("/data/x"), again.state.value.shortcuts.bookmarks)
        assertEquals(listOf("/data/y"), again.state.value.shortcuts.recents)
    }
}
