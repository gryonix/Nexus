package com.skaymer.gryonixnexus.app.files

import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.NodeCapability
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.RemoteFileBrowser
import com.skaymer.gryonixnexus.servercontrol.RemoteFileEntry
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import java.io.IOException
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** The remote file browser */
class FileBrowserViewModelTests {
    private fun server() = Deployment(
        id = "S-1",
        name = "middle",
        topology = Topology.SINGLE_HOST,
        domain = "example.test",
        entry = HostEndpoint(host = "203.0.113.40", user = "root"),
        services = emptySet(),
    )

    private fun file(directory: String, name: String, size: Long = 10) = RemoteFileEntry(
        name = name,
        path = if (directory == "/") "/$name" else "$directory/$name",
        kind = RemoteFileEntry.Kind.FILE,
        size = size,
        permissions = 0x8180,
    )

    private fun directory(parent: String, name: String) = RemoteFileEntry(
        name = name,
        path = if (parent == "/") "/$name" else "$parent/$name",
        kind = RemoteFileEntry.Kind.DIRECTORY,
        size = 4096,
        permissions = 0x41ED,
    )

    private class Scripted(
        val home: String = "/home/admin",
        val homes: Map<SSHHostID, String> = emptyMap(),
        val listings: MutableMap<String, () -> List<RemoteFileEntry>> = mutableMapOf(),
        val download: (String) -> ByteArray = { ByteArray(0) },
        val upload: (String, ByteArray) -> Unit = { _, _ -> },
        val delete: (RemoteFileEntry) -> Unit = {},
    ) : RemoteFileBrowser {
        val asked = mutableListOf<String>()
        val hosts = mutableListOf<SSHHostID>()
        var uploaded: Pair<String, ByteArray>? = null
        var deleted: RemoteFileEntry? = null

        override suspend fun homeDirectory(host: SSHHostID): String {
            asked += "home"
            hosts += host
            return homes[host] ?: home
        }

        override suspend fun listDirectory(path: String, host: SSHHostID): List<RemoteFileEntry> {
            asked += "ls $path"
            hosts += host
            val listing = listings[path] ?: throw IOException("No such file or directory: $path")
            return listing()
        }

        override suspend fun downloadFile(path: String, host: SSHHostID, maxBytes: Long): ByteArray {
            asked += "get $path"
            hosts += host
            return download(path)
        }

        override suspend fun uploadFile(data: ByteArray, path: String, host: SSHHostID) {
            asked += "put $path"
            hosts += host
            uploaded = path to data
            upload(path, data)
        }

        override suspend fun deleteFile(entry: RemoteFileEntry, host: SSHHostID) {
            asked += "rm ${entry.path}"
            hosts += host
            deleted = entry
            delete(entry)
        }
    }

    private fun model(scope: CoroutineScope, disk: Scripted, onRelease: () -> Unit = {}) =
        FileBrowserViewModel(
            scope = scope,
            browsers = { disk },
            release = { onRelease() },
        )

    @Test
    fun `the first look lands where the login user lands`() = runTest(StandardTestDispatcher()) {
        val disk = Scripted(
            listings = mutableMapOf(
                "/home/admin" to { listOf(file("/home/admin", "notes.txt")) },
            ),
        )
        val files = model(this, disk)
        files.start(server())
        runCurrent()

        assertEquals("/home/admin", files.state.value.path)
        assertEquals(listOf("notes.txt"), files.state.value.entries.map { it.name })
        assertEquals(listOf("home", "ls /home/admin"), disk.asked)
    }

    @Test
    fun `a listing is shown in the shared order, directories first`() =
        runTest(StandardTestDispatcher()) {
            val disk = Scripted(
                listings = mutableMapOf(
                    "/home/admin" to {
                        listOf(
                            file("/home/admin", "beta.txt"),
                            directory("/home/admin", "zeta"),
                            file("/home/admin", "Alpha.txt"),
                            directory("/home/admin", "amber"),
                        )
                    },
                ),
            )
            val files = model(this, disk)
            files.start(server())
            runCurrent()

            assertEquals(
                listOf("amber", "zeta", "Alpha.txt", "beta.txt"),
                files.state.value.entries.map { it.name },
            )
        }

    @Test
    fun `a directory that cannot be read leaves you where you were`() =
        runTest(StandardTestDispatcher()) {
            val disk = Scripted(
                listings = mutableMapOf(
                    "/home/admin" to { listOf(directory("/home/admin", "private")) },
                ),
            )
            val files = model(this, disk)
            files.start(server())
            runCurrent()

            files.open(server(), directory("/home/admin", "private"))
            runCurrent()

            val state = files.state.value
            assertEquals("/home/admin", state.path)
            assertEquals(listOf("private"), state.entries.map { it.name })
            assertTrue(state.errorMessage!!.contains("private"))
            assertFalse(state.saysItIsEmpty)
        }

    @Test
    fun `an empty directory and one that could not be read are different sentences`() =
        runTest(StandardTestDispatcher()) {
            val disk = Scripted(listings = mutableMapOf("/home/admin" to { emptyList() }))
            val files = model(this, disk)
            files.start(server())
            runCurrent()
            assertTrue(files.state.value.saysItIsEmpty)

            val broken = Scripted(listings = mutableMapOf())
            val second = model(this, broken)
            second.start(server())
            runCurrent()
            assertTrue(second.state.value.hasAnswered)
            assertTrue(second.state.value.entries.isEmpty())
            assertFalse(second.state.value.saysItIsEmpty)
        }

    @Test
    fun `walking up goes to the parent, and the root has nowhere to go`() =
        runTest(StandardTestDispatcher()) {
            val disk = Scripted(
                home = "/",
                listings = mutableMapOf(
                    "/" to { listOf(directory("/", "opt")) },
                    "/opt" to { listOf(directory("/opt", "backups")) },
                    "/opt/backups" to { emptyList() },
                ),
            )
            val files = model(this, disk)
            files.start(server())
            runCurrent()
            files.open(server(), directory("/", "opt"))
            runCurrent()
            files.open(server(), directory("/opt", "backups"))
            runCurrent()
            assertEquals("/opt/backups", files.state.value.path)

            files.goUp(server())
            runCurrent()
            assertEquals("/opt", files.state.value.path)
            files.goUp(server())
            runCurrent()
            assertEquals("/", files.state.value.path)

            val beforeRoot = disk.asked.size
            files.goUp(server())
            runCurrent()
            assertEquals("/", files.state.value.path)
            assertEquals(beforeRoot, disk.asked.size)
        }

    @Test
    fun `a directory is never downloaded`() = runTest(StandardTestDispatcher()) {
        val disk = Scripted(
            listings = mutableMapOf(
                "/home/admin" to { listOf(directory("/home/admin", "logs")) },
            ),
        )
        val files = model(this, disk)
        files.start(server())
        runCurrent()

        var handed: DownloadedFile? = null
        files.download(server(), directory("/home/admin", "logs")) { handed = it }
        runCurrent()

        assertNull(handed)
        assertFalse(disk.asked.any { it.startsWith("get ") })
    }

    @Test
    fun `a downloaded file is handed over, not written anywhere by this model`() =
        runTest(StandardTestDispatcher()) {
            val disk = Scripted(
                listings = mutableMapOf(
                    "/home/admin" to { listOf(file("/home/admin", "notes.txt")) },
                ),
                download = { "hello".toByteArray() },
            )
            val files = model(this, disk)
            files.start(server())
            runCurrent()

            var handed: DownloadedFile? = null
            files.download(server(), file("/home/admin", "notes.txt")) { handed = it }
            runCurrent()

            assertEquals("notes.txt", handed?.name)
            assertEquals("hello", handed?.bytes?.decodeToString())
            assertNull(files.state.value.transfer)
        }

    @Test
    fun `an upload lands in the directory on screen and the server is re-read`() =
        runTest(StandardTestDispatcher()) {
            var listing = listOf(file("/opt", "old.txt"))
            val disk = Scripted(
                home = "/opt",
                listings = mutableMapOf("/opt" to { listing }),
                upload = { path, _ ->
                    listing = listing + file("/opt", path.substringAfterLast('/'))
                },
            )
            val files = model(this, disk)
            files.start(server())
            runCurrent()

            files.upload(server(), "new.txt", "bytes".toByteArray())
            runCurrent()

            assertEquals("/opt/new.txt", disk.uploaded?.first)
            assertEquals(listOf("new.txt", "old.txt"), files.state.value.entries.map { it.name })
            assertTrue(disk.asked.count { it == "ls /opt" } >= 2)
        }

    @Test
    fun `a delete is followed by re-reading the directory`() = runTest(StandardTestDispatcher()) {
        var listing = listOf(file("/opt", "old.txt"), file("/opt", "keep.txt"))
        val disk = Scripted(
            home = "/opt",
            listings = mutableMapOf("/opt" to { listing }),
            delete = { entry -> listing = listing.filterNot { it.path == entry.path } },
        )
        val files = model(this, disk)
        files.start(server())
        runCurrent()

        files.delete(server(), file("/opt", "old.txt"))
        runCurrent()

        assertEquals(listOf("keep.txt"), files.state.value.entries.map { it.name })
    }

    @Test
    fun `a failed call keeps the rows and says why beside them`() =
        runTest(StandardTestDispatcher()) {
            var fails = false
            val disk = Scripted(
                home = "/opt",
                listings = mutableMapOf(
                    "/opt" to {
                        if (fails) throw IOException("Connection closed")
                        listOf(file("/opt", "keep.txt"))
                    },
                ),
            )
            var released = 0
            val files = model(this, disk) { released += 1 }
            files.start(server())
            runCurrent()

            fails = true
            files.refresh(server())
            runCurrent()

            val state = files.state.value
            assertEquals(listOf("keep.txt"), state.entries.map { it.name })
            assertEquals("Connection closed", state.errorMessage)
            assertFalse(state.isLoading)
            assertEquals(1, released)
        }

    @Test
    fun `a pick larger than the transfer limit is refused before it is read`() {
        assertTrue(FileBrowserViewModel.canSend(null))
        assertTrue(FileBrowserViewModel.canSend(FileBrowserViewModel.TRANSFER_LIMIT_BYTES))
        assertFalse(FileBrowserViewModel.canSend(FileBrowserViewModel.TRANSFER_LIMIT_BYTES + 1))
    }

    @Test
    fun `only files state a size`() {
        assertEquals("2 K", FileBrowserViewModel.sizeLabel(file("/opt", "a.txt", size = 2048)))
        assertNull(FileBrowserViewModel.sizeLabel(directory("/opt", "logs")))
    }

    @Test
    fun `every call names the machine being browsed`() = runTest(StandardTestDispatcher()) {
        val base = server()
        val second = DeploymentNode(
            id = "33333333-3333-3333-3333-333333333333",
            endpoint = HostEndpoint(host = "192.168.1.50", user = "root"),
            capabilities = setOf(NodeCapability.WORKER),
        )
        val deployment = base.copy(storedNodes = base.derivedNodes + second)
        val disk = Scripted(
            listings = mutableMapOf(
                "/home/admin" to { listOf(file("/home/admin", "notes.txt")) },
            ),
        )
        val files = model(this, disk)

        files.start(deployment)
        runCurrent()
        assertEquals(deployment.servicesHost, files.state.value.host, "the first look opens the default worker")
        assertTrue(disk.hosts.all { it == deployment.servicesHost }, "${disk.asked} on ${disk.hosts}")

        disk.hosts.clear()
        files.open(deployment, second.sshHost)
        runCurrent()
        assertEquals(second.sshHost, files.state.value.host)
        assertEquals("/home/admin", files.state.value.path, "the switch lands on that machine's home")

        files.delete(deployment, file("/home/admin", "notes.txt"))
        runCurrent()
        assertTrue(disk.asked.any { it.startsWith("rm ") }, "${disk.asked}")
        assertTrue(
            disk.hosts.all { it == second.sshHost },
            "a call went to another machine: ${disk.asked} on ${disk.hosts}",
        )
    }

    /** Switching machines does NOT carry the path across */
    @Test
    fun `switching machines lands on that machine's own home`() = runTest(StandardTestDispatcher()) {
        val base = server()
        val second = DeploymentNode(
            id = "33333333-3333-3333-3333-333333333333",
            endpoint = HostEndpoint(host = "192.168.1.50", user = "root"),
            capabilities = setOf(NodeCapability.WORKER),
        )
        val deployment = base.copy(storedNodes = base.derivedNodes + second)
        val disk = Scripted(
            // The second machine lands its login user somewhere else, which is
            // what makes "kept the old path" and "asked the new machine"
            // distinguishable at all.
            homes = mapOf(second.sshHost to "/root"),
            listings = mutableMapOf(
                "/home/admin" to { listOf(file("/home/admin", "notes.txt")) },
                "/home/admin/deep" to { listOf(file("/home/admin/deep", "b")) },
                "/root" to { listOf(file("/root", "elsewhere.txt")) },
            ),
        )
        val files = model(this, disk)
        files.start(deployment)
        runCurrent()
        files.open(deployment, directory("/home/admin", "deep"))
        runCurrent()
        assertEquals("/home/admin/deep", files.state.value.path)

        files.open(deployment, second.sshHost)
        runCurrent()
        assertEquals("/root", files.state.value.path)
        assertEquals("ls /root", disk.asked.last(), "${disk.asked}")
        assertEquals(listOf("elsewhere.txt"), files.state.value.entries.map { it.name },
                     "the previous machine's rows are still on screen")
    }

    /**
     * **Tapping the machine already on screen asks for nothing.** The refresh
     * button is what re-reads a directory; answering a tick with a fresh
     * handshake would put one more connection into the burst OpenSSH answers
     * with per-source penalties — the same reason the metrics poller backs off
     * and the relay probes are behind a button.
     *
     * And the machine is chosen SYNCHRONOUSLY, because the picker draws its
     * tick from it: a selection that only becomes true when a background job
     * starts is a list with nothing selected for as long as the dispatcher
     * takes.
     */
    @Test
    fun `re-picking the machine already open asks the server nothing`() = runTest(StandardTestDispatcher()) {
        val base = server()
        val second = DeploymentNode(
            id = "33333333-3333-3333-3333-333333333333",
            endpoint = HostEndpoint(host = "192.168.1.50", user = "root"),
            capabilities = setOf(NodeCapability.WORKER),
        )
        val deployment = base.copy(storedNodes = base.derivedNodes + second)
        val disk = Scripted(
            listings = mutableMapOf("/home/admin" to { listOf(file("/home/admin", "notes.txt")) }),
        )
        val files = model(this, disk)
        files.start(deployment)
        runCurrent()
        val asked = disk.asked.size

        files.open(deployment, deployment.servicesHost)
        runCurrent()
        assertEquals(asked, disk.asked.size, "a redundant handshake: ${disk.asked}")

        // The other machine is a real request, and the tick moves before the
        // dispatcher has run anything at all.
        files.open(deployment, second.sshHost)
        assertEquals(second.sshHost, files.state.value.host, "the picker would draw nothing selected")
    }

    @Test
    fun `changing servers forgets the directory`() = runTest(StandardTestDispatcher()) {
        val disk = Scripted(listings = mutableMapOf("/home/admin" to { listOf(file("/home/admin", "a")) }))
        val files = model(this, disk)
        files.start(server())
        runCurrent()
        assertEquals("/home/admin", files.state.value.path)

        files.reset()
        assertEquals(FileBrowserState(), files.state.value)
    }
}
