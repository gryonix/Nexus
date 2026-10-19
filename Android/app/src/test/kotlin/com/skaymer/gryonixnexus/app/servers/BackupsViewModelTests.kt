package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.agentcontrol.PreRestoreCopy
import com.skaymer.gryonixnexus.agentcontrol.PreRestoreManaging
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.servercontrol.AutoBackupSettings
import com.skaymer.gryonixnexus.servercontrol.BackupDestinationSettings
import com.skaymer.gryonixnexus.servercontrol.BackupDestinationState
import com.skaymer.gryonixnexus.servercontrol.BackupDestinationTestResult
import com.skaymer.gryonixnexus.servercontrol.BackupEntry
import com.skaymer.gryonixnexus.servercontrol.FleetBackup
import com.skaymer.gryonixnexus.servercontrol.BackupEstimate
import com.skaymer.gryonixnexus.servercontrol.BackupOutcome
import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.NodeCapability
import com.skaymer.gryonixnexus.servercontrol.ServicePlacement
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.ServiceBackupManaging
import com.skaymer.gryonixnexus.servercontrol.ServiceRestoreManaging
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.CoroutineScope
import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.RemoteFileBrowser
import com.skaymer.gryonixnexus.servercontrol.RemoteFileEntry
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import kotlin.time.Duration
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

/** Backups for one server */
class BackupsViewModelTests {
    private val nextcloud = ServiceID.NEXTCLOUD
    private val vaultwarden = ServiceID.VAULTWARDEN
    private val openvpn = ServiceID.OPEN_VPN

    private fun server(services: Set<ServiceID> = setOf(nextcloud, vaultwarden, openvpn)) =
        Deployment(
            id = "S-1",
            name = "middle",
            topology = Topology.SINGLE_HOST,
            domain = "example.test",
            entry = HostEndpoint(host = "203.0.113.40", user = "root"),
            services = services,
        )

    private fun service(id: ServiceID): ManagedService = ServiceRegistry.service(id)!!

    /** A backup seam that answers from a script */
    private class Scripted(
        val list: () -> List<BackupEntry> = { emptyList() },
        val estimate: () -> BackupEstimate? = { null },
        val run: ((String) -> Unit) -> BackupOutcome = { BackupOutcome(1, "/a.tgz", "") },
        val delete: (String) -> Unit = {},
    ) : ServiceBackupManaging {
        val asked = mutableListOf<String>()
        var encryptedWith: Pair<Boolean?, String?>? = null

        override suspend fun listBackups(service: ManagedService): List<BackupEntry> {
            asked += "list"
            return list.invoke()
        }

        override suspend fun estimate(service: ManagedService): BackupEstimate? {
            asked += "estimate"
            return estimate.invoke()
        }

        override suspend fun backup(
            service: ManagedService,
            encrypt: Boolean?,
            passphrase: String?,
            onChunk: (String) -> Unit,
        ): BackupOutcome {
            asked += "backup"
            encryptedWith = encrypt to passphrase
            return run.invoke(onChunk)
        }

        override suspend fun deleteBackup(service: ManagedService, path: String) {
            asked += "delete:$path"
            delete.invoke(path)
        }
    }

    private class ScriptedRestore(
        val body: (String, String?, (String) -> Unit) -> String = { _, _, _ -> "" },
    ) : ServiceRestoreManaging {
        var restoredPath: String? = null
        var passphrase: String? = null

        override suspend fun restore(
            service: ManagedService,
            archivePath: String,
            passphrase: String?,
            onChunk: (String) -> Unit,
        ): String {
            restoredPath = archivePath
            this.passphrase = passphrase
            return body(archivePath, passphrase, onChunk)
        }
    }

    private class ScriptedSchedule(
        val load: () -> AutoBackupSettings = { AutoBackupSettings() },
        val save: (AutoBackupSettings, String?) -> Unit = { _, _ -> },
        val destination: () -> BackupDestinationState = { BackupDestinationState() },
        val test: () -> BackupDestinationTestResult = { BackupDestinationTestResult(true) },
    ) : BackupScheduleManaging {
        var saved: AutoBackupSettings? = null
        var savedPassphrase: String? = null
        var savedDestination: BackupDestinationSettings? = null
        var savedSecret: String? = null

        override suspend fun load(): AutoBackupSettings = load.invoke()

        override suspend fun save(settings: AutoBackupSettings, passphrase: String?) {
            saved = settings
            savedPassphrase = passphrase
            save.invoke(settings, passphrase)
        }

        override suspend fun loadDestination(): BackupDestinationState = destination.invoke()

        override suspend fun saveDestination(
            settings: BackupDestinationSettings,
            secret: String?,
        ) {
            savedDestination = settings
            savedSecret = secret
        }

        override suspend fun testDestination(): BackupDestinationTestResult = test.invoke()
    }

    /** The SFTP seam, scripted */
    private class ScriptedBrowser(
        var download: (String) -> ByteArray = { error("no download expected: ${'$'}it") },
        var upload: (ByteArray, String) -> Unit = { _, path -> error("no upload expected: ${'$'}path") },
    ) : RemoteFileBrowser {
        var downloaded: String? = null
        var uploaded: String? = null
        var downloadedFrom: SSHHostID? = null

        override suspend fun homeDirectory(host: SSHHostID): String = "/root"
        override suspend fun listDirectory(path: String, host: SSHHostID) = emptyList<RemoteFileEntry>()
        override suspend fun downloadFile(path: String, host: SSHHostID, maxBytes: Long): ByteArray {
            downloaded = path
            downloadedFrom = host
            return download(path)
        }
        override suspend fun uploadFile(data: ByteArray, path: String, host: SSHHostID) {
            uploaded = path
            upload(data, path)
        }
        override suspend fun deleteFile(entry: RemoteFileEntry, host: SSHHostID) = Unit
    }

    /** Enough of a runner for the upload's own staging step */
    private class QuietRunner : SSHCommandRunner {
        val commands = mutableListOf<String>()
        override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult {
            commands += command
            return ExecResult(exitCode = 0, stdout = "", stderr = "")
        }
        override fun stream(command: String, host: SSHHostID, timeout: Duration) =
            kotlinx.coroutines.flow.emptyFlow<ExecChunk>()
        override suspend fun fireAndForget(command: String, host: SSHHostID) = Unit
        override suspend fun disconnect() = Unit
    }

    private fun model(
        scope: CoroutineScope,
        backups: ServiceBackupManaging = Scripted(),
        restores: ServiceRestoreManaging = ScriptedRestore(),
        schedules: BackupScheduleManaging = ScriptedSchedule(),
        browser: RemoteFileBrowser = ScriptedBrowser(),
        transferRunner: SSHCommandRunner = QuietRunner(),
        onRelease: () -> Unit = {},
        oldCopies: PreRestoreManaging? = null,
    ) = BackupsViewModel(
        scope = scope,
        backups = { _, _ -> backups },
        restores = { _, _ -> restores },
        schedules = { schedules },
        browsers = { browser },
        runners = { transferRunner },
        release = { onRelease() },
        oldCopies = { _, _ -> oldCopies },
    )

    private class ScriptedCopies(var held: List<PreRestoreCopy>) : PreRestoreManaging {
        val deleted = mutableListOf<String>()

        override suspend fun copies(service: ManagedService) = held

        override suspend fun delete(copy: PreRestoreCopy): List<PreRestoreCopy> {
            deleted += copy.path
            held = held.filter { it.path != copy.path }
            return held
        }
    }

    private fun oldCopy(path: String) = PreRestoreCopy("nextcloud", path, 10, true, 1)

    private fun entry(name: String) = BackupEntry(name, "512M", "Jul 10 03:00")

    // ------------------------------------------------- Between device and host

    @Test
    fun `saving an archive reads it by its resolved path`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val browser = ScriptedBrowser(download = { "archive".toByteArray() })
        val model = model(scope, browser = browser)
        var handed: Pair<ByteArray, String>? = null

        model.download(server(), nextcloud, entry("nextcloud-20260829.tar.gz")) { bytes, name ->
            handed = bytes to name
        }
        advanceUntilIdle()

        assertEquals("/opt/backups/nextcloud/nextcloud-20260829.tar.gz", browser.downloaded)
        assertEquals("archive", handed?.first?.decodeToString())
        assertEquals("nextcloud-20260829.tar.gz", handed?.second)
        assertNull(model.state.value.services[nextcloud]?.transfer, "the transfer is over")
    }

    /** And off the machine that RUNS the service */
    @Test
    fun `saving an archive reads it off the machine that runs the service`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val base = server()
        val third = DeploymentNode(
            id = "33333333-3333-3333-3333-333333333333",
            endpoint = HostEndpoint(host = "10.8.0.3", user = "root"),
            capabilities = setOf(NodeCapability.WORKER),
            routedThrough = base.ingressNode?.id,
        )
        val placed = base.copy(
            storedNodes = base.derivedNodes + third,
            placement = ServicePlacement(mapOf(nextcloud.rawValue to third.id)),
        )
        val browser = ScriptedBrowser(download = { "archive".toByteArray() })
        val model = model(scope, browser = browser)

        model.download(placed, nextcloud, entry("nextcloud-20260829.tar.gz")) { _, _ -> }
        advanceUntilIdle()
        assertEquals(SSHHostID.node(third.id), browser.downloadedFrom)

        model.download(placed, vaultwarden, entry("vaultwarden-20260829.tar.gz")) { _, _ -> }
        advanceUntilIdle()
        assertEquals(placed.servicesHost, browser.downloadedFrom)
    }

    @Test
    fun `a failed download reports and hands nothing over`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val browser = ScriptedBrowser(download = { error("connection reset") })
        val model = model(scope, browser = browser)
        var handed = false

        model.download(server(), nextcloud, entry("x.tar.gz")) { _, _ -> handed = true }
        advanceUntilIdle()

        assertFalse(handed, "nothing may be written when nothing arrived")
        assertTrue(
            model.state.value.services[nextcloud]?.errorMessage?.contains("connection reset") == true,
            model.state.value.services[nextcloud]?.errorMessage ?: "no error reported",
        )
        assertNull(model.state.value.services[nextcloud]?.transfer)
    }

    @Test
    fun `a file from the device is uploaded and then restored`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val browser = ScriptedBrowser(upload = { _, _ -> })
        val restores = ScriptedRestore()
        val model = model(scope, restores = restores, browser = browser)

        model.restoreFromDevice(
            server(), nextcloud, "archive".toByteArray(), "carried.tar.gz.gpg", "secret",
        )
        advanceUntilIdle()

        assertTrue(browser.uploaded?.endsWith("carried.tar.gz.gpg") == true, browser.uploaded ?: "")
        assertEquals(browser.uploaded, restores.restoredPath, "the restore runs on what was uploaded")
        assertEquals("secret", restores.passphrase)
    }

    @Test
    fun `a failed upload never starts a restore`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val browser = ScriptedBrowser(upload = { _, _ -> error("no space left on device") })
        val restores = ScriptedRestore()
        val model = model(scope, restores = restores, browser = browser)

        model.restoreFromDevice(server(), nextcloud, "archive".toByteArray(), "x.tar.gz", null)
        advanceUntilIdle()

        assertNull(restores.restoredPath, "a restore on a half-sent archive is worse than none")
        assertTrue(
            model.state.value.services[nextcloud]?.errorMessage?.contains("no space") == true,
            model.state.value.services[nextcloud]?.errorMessage ?: "no error reported",
        )
    }

    // ------------------------------------------------------------- Listing

    @Test
    fun `an answered empty listing is the server saying there are none`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope)
        model.list(server(), nextcloud)
        runCurrent()

        val state = model.state.value.services[nextcloud]!!
        assertTrue(state.hasAnswered)
        assertTrue(state.saysThereAreNone)
    }

    @Test
    fun `the whole list holds every service of the server`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope, backups = Scripted(list = { listOf(entry("a.tar.gz"), entry("b.tar.gz")) }))
        model.loadAll(server(setOf(nextcloud)))
        runCurrent()

        val all = model.all.value
        assertTrue(all.hasLoaded)
        assertEquals(2, all.rows.size)
        assertEquals(null, all.failure)
    }

    @Test
    fun `several backups are deleted one by one and the list is read again`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val seam = Scripted(list = { listOf(entry("a.tar.gz"), entry("b.tar.gz")) })
        val model = model(scope, backups = seam)
        val deployment = server(setOf(nextcloud))
        model.loadAll(deployment)
        runCurrent()

        model.deleteMany(deployment, listOf(nextcloud to entry("a.tar.gz"), nextcloud to entry("b.tar.gz")))
        runCurrent()

        assertEquals(2, seam.asked.count { it.startsWith("delete:") })
        assertEquals(2, seam.asked.count { it == "list" }, "read once at the start and again after the deletes")
        assertNull(model.all.value.actionError)
    }

    @Test
    fun `a delete that fails is reported and the rest still go`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        var first = true
        val seam = Scripted(delete = {
            if (first) {
                first = false
                error("busy")
            }
        })
        val model = model(scope, backups = seam)
        val deployment = server(setOf(nextcloud))

        model.deleteMany(deployment, listOf(nextcloud to entry("a.tar.gz"), nextcloud to entry("b.tar.gz")))
        runCurrent()

        assertEquals(2, seam.asked.count { it.startsWith("delete:") })
        assertEquals("busy", model.all.value.actionError)
    }

    @Test
    fun `a server that never answers is given up on and says why`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val stuck = object : ServiceBackupManaging by Scripted() {
            override suspend fun listBackups(service: ManagedService): List<BackupEntry> {
                delay(Long.MAX_VALUE)
                return emptyList()
            }
        }
        val model = model(scope, backups = stuck)
        model.loadAll(server(setOf(nextcloud)))
        runCurrent()
        assertTrue(model.all.value.isLoading)

        advanceTimeBy(BackupsViewModel.ALL_DEADLINE_MILLIS + 1)
        runCurrent()

        assertTrue(model.all.value.hasLoaded)
        assertTrue(model.all.value.failure != null)
    }

    @Test
    fun `listing a service also reads the old copies its restores left`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val copies = ScriptedCopies(listOf(oldCopy("/opt/nextcloud/data.pre-restore-1")))
        val model = model(scope, oldCopies = copies)
        model.list(server(), nextcloud)
        runCurrent()

        assertEquals(1, model.state.value.oldCopies[nextcloud]!!.size)
    }

    @Test
    fun `deleting an old copy keeps only what the agent says is left`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val first = oldCopy("/opt/nextcloud/data.pre-restore-1")
        val second = oldCopy("/opt/nextcloud/data.pre-restore-2")
        val copies = ScriptedCopies(listOf(first, second))
        val model = model(scope, oldCopies = copies)
        model.list(server(), nextcloud)
        runCurrent()

        model.deleteOldCopy(server(), nextcloud, first)
        runCurrent()

        assertEquals(listOf(first.path), copies.deleted)
        assertEquals(listOf(second), model.state.value.oldCopies[nextcloud])
    }

    @Test
    fun `a refused delete shows its reason and keeps the copies`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val copy = oldCopy("/opt/nextcloud/data.pre-restore-1")
        val failing = object : PreRestoreManaging {
            override suspend fun copies(service: ManagedService) = listOf(copy)
            override suspend fun delete(copy: PreRestoreCopy): List<PreRestoreCopy> = error("busy")
        }
        val model = model(scope, oldCopies = failing)
        model.list(server(), nextcloud)
        runCurrent()

        model.deleteOldCopy(server(), nextcloud, copy)
        runCurrent()

        assertEquals(listOf(copy), model.state.value.oldCopies[nextcloud])
        assertEquals("busy", model.state.value.services[nextcloud]!!.errorMessage)
    }

    @Test
    fun `a failed listing never says there are none`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope, backups = Scripted(list = { error("no route to host") }))
        model.list(server(), nextcloud)
        runCurrent()

        val state = model.state.value.services[nextcloud]!!
        assertTrue(state.hasAnswered)
        assertFalse(state.saysThereAreNone)
        assertEquals("no route to host", state.errorMessage)
    }

    @Test
    fun `a failed listing clears the rows it had`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        var fail = false
        val model = model(
            scope,
            backups = Scripted(list = {
                if (fail) error("connection lost") else listOf(entry("a.tgz"))
            }),
        )
        model.list(server(), nextcloud)
        runCurrent()
        assertEquals(1, model.state.value.services[nextcloud]!!.entries.size)

        fail = true
        model.list(server(), nextcloud)
        runCurrent()
        assertEquals(emptyList(), model.state.value.services[nextcloud]!!.entries)
    }

    @Test
    fun `a dropped session is released so the next call redials`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        var released = 0
        val model = model(
            scope,
            backups = Scripted(list = { error("channel closed") }),
            onRelease = { released += 1 },
        )
        model.list(server(), nextcloud)
        runCurrent()
        assertEquals(1, released)
    }

    // -------------------------------------------------------------- Deleting

    @Test
    fun `deleting re-reads the listing from the server`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        var remaining = listOf(entry("a.tgz"), entry("b.tgz"))
        val seam = Scripted(
            list = { remaining },
            delete = { path -> remaining = remaining.filterNot { path.endsWith(it.name) } },
        )
        val model = model(scope, backups = seam)
        model.delete(server(), nextcloud, entry("a.tgz"))
        runCurrent()

        assertEquals(listOf("b.tgz"), model.state.value.services[nextcloud]!!.entries.map { it.name })
        assertTrue(seam.asked.last() == "list", "the listing is re-read after a delete")
    }

    @Test
    fun `a failed delete leaves the entry and says why`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(
            scope,
            backups = Scripted(
                list = { listOf(entry("a.tgz")) },
                delete = { error("permission denied") },
            ),
        )
        model.delete(server(), nextcloud, entry("a.tgz"))
        runCurrent()

        val state = model.state.value.services[nextcloud]!!
        assertEquals(listOf("a.tgz"), state.entries.map { it.name })
    }

    @Test
    fun `the path of an entry follows the shape the listing printed`() {
        val context = server().serviceContext
        val dir = service(nextcloud).actions(context).backup!!.listDirectory
        assertEquals(
            "$dir/a.tgz",
            BackupsViewModel.path(service(nextcloud), context, entry("a.tgz")),
        )
        assertEquals(
            "/opt/elsewhere/a.tgz",
            BackupsViewModel.path(service(nextcloud), context, entry("/opt/elsewhere/a.tgz")),
        )
    }

    @Test
    fun `a service with no backups has no path to delete`() {
        val context = server().serviceContext
        assertNull(BackupsViewModel.path(service(openvpn), context, entry("a.tgz")))
    }

    // ------------------------------------------------------------- Estimate

    @Test
    fun `no estimate is unknown rather than zero`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope, backups = Scripted(estimate = { null }))
        model.estimate(server(), nextcloud)
        runCurrent()

        val state = model.state.value.estimate!!
        assertFalse(state.isLoading)
        assertNull(state.estimate)
        assertNull(state.errorMessage)
    }

    /** A failed estimate is a warning mechanism, not a precondition */
    @Test
    fun `a failed estimate reports and does not block`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val seam = Scripted(estimate = { error("unsupported action") })
        val model = model(scope, backups = seam)
        model.estimate(server(), nextcloud)
        runCurrent()
        assertEquals("unsupported action", model.state.value.estimate!!.errorMessage)

        model.backUp(server(), nextcloud, encrypt = true, passphrase = null)
        runCurrent()
        assertTrue("backup" in seam.asked)
    }

    @Test
    fun `an estimate is never written onto another service's sheet`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val slow = Scripted(estimate = { error("unused") })
        val model = BackupsViewModel(
            scope = scope,
            backups = { _, service ->
                if (service.id == nextcloud) {
                    object : ServiceBackupManaging by slow {
                        override suspend fun estimate(service: ManagedService): BackupEstimate {
                            delay(1000)
                            return BackupEstimate(dataBytes = 111, freeBytes = 111)
                        }
                    }
                } else {
                    Scripted(estimate = { BackupEstimate(dataBytes = 222, freeBytes = 222) })
                }
            },
            restores = { _, _ -> ScriptedRestore() },
            schedules = { ScriptedSchedule() },
            browsers = { ScriptedBrowser() },
            runners = { QuietRunner() },
        )
        model.estimate(server(), nextcloud)
        runCurrent()
        model.estimate(server(), vaultwarden)
        runCurrent()
        advanceUntilIdle()

        val shown = model.state.value.estimate!!
        assertEquals(vaultwarden, shown.service)
        assertEquals(222, shown.estimate!!.dataBytes)
    }

    @Test
    fun `the disk warnings answer only when the server gave numbers`() {
        assertFalse(BackupsViewModel.doesNotFit(null))
        assertFalse(BackupsViewModel.isLarge(null))
        assertTrue(BackupsViewModel.doesNotFit(BackupEstimate(dataBytes = 20, freeBytes = 10)))
        assertFalse(BackupsViewModel.doesNotFit(BackupEstimate(dataBytes = 10, freeBytes = 20)))
        assertTrue(
            BackupsViewModel.isLarge(
                BackupEstimate(BackupsViewModel.LARGE_BACKUP_BYTES, Long.MAX_VALUE)
            )
        )
        assertFalse(
            BackupsViewModel.isLarge(
                BackupEstimate(BackupsViewModel.LARGE_BACKUP_BYTES - 1, Long.MAX_VALUE)
            )
        )
    }

    // ---------------------------------------------------------------- Runs

    /**
     * `null` means "whatever this service does by default", and it has to reach
     * the wrapper as null: the per-service default (secret stores encrypt, photo
     * libraries do not) is knowledge the server holds, and deciding it here
     * would make the app the second place that has an opinion.
     */
    @Test
    fun `an untouched encryption switch is passed through undecided`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val seam = Scripted()
        val model = model(scope, backups = seam)
        model.backUp(server(), nextcloud, encrypt = null, passphrase = null)
        runCurrent()

        assertEquals(null to null, seam.encryptedWith)
    }

    /** The wrapper's markers are addressed to the app, not to the reader. */
    @Test
    fun `the run log reaches the screen without protocol in it`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val seam = Scripted(run = { onChunk ->
            onChunk("Creating archive…\nGRYONIXNEXUS_BACKUP_DONE 377608287 /opt/backups/a.tgz\n")
            onChunk("GRYONIXNEXUS_BACKUP_CTL_DONE\n")
            BackupOutcome(377608287, "/opt/backups/a.tgz", "")
        })
        val model = model(scope, backups = seam)
        model.backUp(server(), nextcloud, encrypt = false, passphrase = null)
        runCurrent()

        val run = model.state.value.run!!
        assertFalse("GRYONIXNEXUS" in run.log, "a protocol token is on screen:\n${run.log}")
        assertTrue("Creating archive" in run.log)
        assertEquals(377608287, run.sizeBytes)
        assertTrue(run.isFinished)
    }

    @Test
    fun `a run that failed is finished with a reason and not a size`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope, backups = Scripted(run = { error("no space left on device") }))
        model.backUp(server(), nextcloud, encrypt = false, passphrase = null)
        runCurrent()

        val run = model.state.value.run!!
        assertTrue(run.isFinished)
        assertNull(run.sizeBytes)
        assertEquals("no space left on device", run.errorMessage)
    }

    @Test
    fun `a finished run re-reads the directory whether it worked or not`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val seam = Scripted(run = { error("interrupted") }, list = { listOf(entry("half.tgz")) })
        val model = model(scope, backups = seam)
        model.backUp(server(), nextcloud, encrypt = false, passphrase = null)
        runCurrent()

        assertEquals(listOf("half.tgz"), model.state.value.services[nextcloud]!!.entries.map { it.name })
    }

    @Test
    fun `a restore sends the archive it was given and streams its log`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val seam = ScriptedRestore { _, _, onChunk ->
            onChunk("Stopping containers\nGRYONIXNEXUS_RESTORE_DONE\n")
            ""
        }
        val model = model(scope, restores = seam)
        model.restore(server(), vaultwarden, "/opt/backups/vw/a.tar.gz.gpg", "hunter22")
        runCurrent()

        assertEquals("/opt/backups/vw/a.tar.gz.gpg", seam.restoredPath)
        assertEquals("hunter22", seam.passphrase)
        val run = model.state.value.run!!
        assertEquals(BackupRun.Kind.RESTORE, run.kind)
        assertFalse("GRYONIXNEXUS" in run.log, "a protocol token is on screen:\n${run.log}")
        assertTrue(run.isFinished)
    }

    @Test
    fun `whether a restore needs a passphrase is read off the archive`() {
        val context = server().serviceContext
        assertTrue(
            BackupsViewModel.restoreNeedsPassphrase(
                service(nextcloud), context, "/opt/backups/nextcloud/a.tar.gz.gpg"
            )
        )
        assertFalse(
            BackupsViewModel.restoreNeedsPassphrase(
                service(nextcloud), context, "/opt/backups/nextcloud/a.tar.gz"
            )
        )
        // vaultwarden's every archive is encrypted, whatever the name says.
        assertTrue(
            BackupsViewModel.restoreNeedsPassphrase(
                service(vaultwarden), context, "/opt/backups/vaultwarden/a.tar.gz"
            )
        )
    }

    // ------------------------------------------------------------ Schedule

    /** "Off" is a claim about the machine */
    @Test
    fun `the schedule is silent until the machine has answered`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope)
        assertFalse(model.state.value.hasLoadedSchedule)

        model.loadSchedule(server())
        runCurrent()
        assertTrue(model.state.value.hasLoadedSchedule)
    }

    @Test
    fun `a schedule that could not be read is reported and not assumed off`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope, schedules = ScriptedSchedule(load = { error("sudo: not allowed") }))
        model.loadSchedule(server())
        runCurrent()

        assertEquals("sudo: not allowed", model.state.value.scheduleError)
        assertFalse(model.state.value.hasLoadedSchedule)
    }

    @Test
    fun `the schedule moves only when the machine confirms`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val wanted = AutoBackupSettings(
            schedule = CommandCatalog.Backups.Schedule.Days(1, 3, 0),
            retention = 7,
            services = setOf(nextcloud.rawValue),
        )
        val model = model(scope, schedules = ScriptedSchedule(save = { _, _ -> error("write failed") }))
        model.saveSchedule(server(), wanted, null)
        runCurrent()

        assertEquals(CommandCatalog.Backups.Schedule.Off, model.state.value.schedule.schedule)
        assertEquals("write failed", model.state.value.scheduleError)
        assertFalse(model.state.value.isSaving)
    }

    @Test
    fun `a confirmed save is what the screen then shows`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val seam = ScriptedSchedule()
        val wanted = AutoBackupSettings(
            schedule = CommandCatalog.Backups.Schedule.Hours(6, 30),
            retention = 3,
            services = setOf(nextcloud.rawValue),
        )
        val model = model(scope, schedules = seam)
        model.saveSchedule(server(), wanted, "hunter22")
        runCurrent()

        assertEquals(wanted, model.state.value.schedule)
        assertEquals("hunter22", seam.savedPassphrase)
        assertTrue(model.state.value.hasLoadedSchedule)
    }

    @Test
    fun `a schedule with no services cannot be saved`() {
        val deployment = server()
        val empty = AutoBackupSettings(
            schedule = CommandCatalog.Backups.Schedule.Days(1, 3, 0),
            services = emptySet(),
        )
        assertFalse(
            BackupsViewModel.canSaveSchedule(deployment, empty, AutoBackupSettings(), "", false)
        )
        assertTrue(
            BackupsViewModel.canSaveSchedule(
                deployment,
                empty.copy(services = setOf(nextcloud.rawValue)),
                AutoBackupSettings(),
                "",
                false,
            )
        )
        assertTrue(
            BackupsViewModel.canSaveSchedule(
                deployment,
                AutoBackupSettings(),
                AutoBackupSettings(),
                "",
                false,
            )
        )
    }

    @Test
    fun `an encrypted service needs a passphrase the machine does not have yet`() {
        val deployment = server()
        val draft = AutoBackupSettings(
            schedule = CommandCatalog.Backups.Schedule.Days(1, 3, 0),
            services = setOf(vaultwarden.rawValue),
        )
        assertTrue(BackupsViewModel.scheduleNeedsPassphrase(deployment, draft))
        assertFalse(
            BackupsViewModel.canSaveSchedule(deployment, draft, AutoBackupSettings(), "", false)
        )
        assertTrue(
            BackupsViewModel.canSaveSchedule(deployment, draft, AutoBackupSettings(), "hunter22", false)
        )
        assertTrue(BackupsViewModel.hasStoredPassphrase(deployment, draft))
        assertTrue(BackupsViewModel.canSaveSchedule(deployment, draft, draft, "", false))
    }

    /** Wrapper-driven services carry no such requirement */
    @Test
    fun `a wrapper-driven schedule needs no stored passphrase`() {
        val deployment = server()
        val draft = AutoBackupSettings(
            schedule = CommandCatalog.Backups.Schedule.Days(1, 3, 0),
            services = setOf(nextcloud.rawValue),
        )
        assertFalse(BackupsViewModel.scheduleNeedsPassphrase(deployment, draft))
        assertFalse(BackupsViewModel.hasStoredPassphrase(deployment, draft))
    }

    @Test
    fun `an off schedule needs no passphrase`() {
        val deployment = server()
        assertFalse(
            BackupsViewModel.scheduleNeedsPassphrase(
                deployment,
                AutoBackupSettings(services = setOf(vaultwarden.rawValue)),
            )
        )
    }

    // -------------------------------------------------------- The offer set

    @Test
    fun `only services with a backup are offered one`() {
        val deployment = server()
        val offered = BackupsViewModel.backupCapableServices(deployment).map { it.id }
        assertTrue(nextcloud in offered)
        assertTrue(vaultwarden in offered)
        assertFalse(openvpn in offered, "a service with no backup spec is offered a backup")
    }

    @Test
    fun `only services with a restore spec are offered one`() {
        val deployment = server()
        val offered = BackupsViewModel.restorableServices(deployment).map { it.id }
        assertTrue(vaultwarden in offered)
        assertFalse(openvpn in offered)
    }

    // ------------------------------------------------------- The passphrase

    @Test
    fun `a typed passphrase must match its repeat`() {
        assertTrue(BackupsViewModel.passphraseIsUsable("", ""))
        assertTrue(BackupsViewModel.passphraseIsUsable("hunter22", "hunter22"))
        assertFalse(BackupsViewModel.passphraseIsUsable("hunter22", "hunter23"))
        assertFalse(BackupsViewModel.passphraseIsUsable("short", "short"))
    }

    @Test
    fun `opening another server shows its own answers`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler))
        val model = model(scope, backups = Scripted(list = { listOf(entry("a.tgz")) }))
        model.list(server(), nextcloud)
        runCurrent()
        assertTrue(model.state.value.services.isNotEmpty())

        model.reset()
        assertEquals(BackupsState(), model.state.value)
    }

    private fun cloudBackup(drive: String? = null) = FleetBackup(
        serverId = "S-1", serverName = "middle", serviceId = nextcloud.rawValue, serviceName = "Nextcloud",
        entry = BackupEntry("nextcloud-1.tar.gz", "1K", "", drive = drive),
    )

    @Test
    fun `a listed backup goes back here or to another server with the same service`() {
        val here = server()
        val other = server().copy(id = "S-2", name = "draco")
        val without = server(services = emptySet()).copy(id = "S-3", name = "vega")
        val targets = BackupsViewModel.restoreTargets(here, cloudBackup(), listOf(without, here, other))
        assertEquals(listOf("middle", "draco"), targets.map { it.name })
    }

    @Test
    fun `a copy on a drive goes back only to its own server`() {
        val here = server()
        val targets = BackupsViewModel.restoreTargets(here, cloudBackup(drive = "usb1"),
            listOf(here, server().copy(id = "S-2", name = "draco")))
        assertEquals(listOf("middle"), targets.map { it.name })
    }
}
