package com.skaymer.gryonixnexus.app.install

import com.skaymer.gryonixnexus.app.access.SudoProblem
import com.skaymer.gryonixnexus.servercontrol.SudoAccess
import com.skaymer.gryonixnexus.servercontrol.RemoteFileEntry
import com.skaymer.gryonixnexus.servercontrol.RemoteFileBrowser
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.core.ArtifactKind
import com.skaymer.gryonixnexus.core.GeneratedBundle
import com.skaymer.gryonixnexus.core.ServerRole
import com.skaymer.gryonixnexus.recipe.SetupMarkers
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.ExecChunk
import com.skaymer.gryonixnexus.servercontrol.ExecResult
import com.skaymer.gryonixnexus.servercontrol.HostEndpoint
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.SetupEvent
import com.skaymer.gryonixnexus.servercontrol.SetupProgressParser
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Test

class InstallViewModelTests {
    // ------------------------------------------------------------- Fixtures

    private fun script(role: ServerRole, distribution: String? = "debian") = Artifact(
        fileName = "setup-${role.name.lowercase()}.sh",
        kind = ArtifactKind.SHELL_SCRIPT,
        contents = buildString {
            appendLine("#!/usr/bin/env bash")
            if (distribution != null) appendLine("# ${SetupMarkers.DISTRIBUTION}: $distribution")
            appendLine("set -euo pipefail")
        },
        summary = "setup",
        server = role,
    )

    private fun singleHostBundle() = GeneratedBundle(artifacts = listOf(script(ServerRole.SINGLE_HOST)))

    private fun pairBundle(homeDistribution: String = "ubuntu") = GeneratedBundle(
        artifacts = listOf(script(ServerRole.VPS_RELAY), script(ServerRole.HOME_BACKEND, homeDistribution))
    )

    private fun server(topology: Topology = Topology.SINGLE_HOST) = Deployment(
        id = "S-1",
        name = "example.com",
        topology = topology,
        domain = "example.com",
        entry = HostEndpoint(host = "203.0.113.10", user = "server-user"),
    )

    private class ProbeRunner(
        private val id: String = "debian",
        private val idLike: String = "",
        private val fails: Int = 0,
        var sudoReady: Boolean = true,
        private val password: String = "right",
    ) : SSHCommandRunner, RemoteFileBrowser {
        var attempts = 0
        var sent: String? = null
        var disconnects = 0
        val commands = mutableListOf<String>()

        override suspend fun run(command: String, host: SSHHostID, timeout: Duration): ExecResult {
            attempts += 1
            commands += command
            if (attempts <= fails) throw IllegalStateException("connection refused")
            if ("mktemp -d" in command) return ExecResult(0, "/tmp/tmp.T\n", "")
            if ("sudo -S" in command) {
                sudoReady = sent == "$password\n"
                return if (sudoReady) ExecResult(0, "${SudoAccess.READY_TOKEN}\n", "")
                else ExecResult(1, "", "sudo: 1 incorrect password attempt\n")
            }
            val sudo = if (sudoReady) "${SudoAccess.READY_TOKEN}\n" else ""
            return ExecResult(
                exitCode = 0,
                stdout = "GRYONIXNEXUS_PING\n${SetupMarkers.DISTRIBUTION}:$id:$idLike\n$sudo",
                stderr = "",
            )
        }

        override suspend fun uploadFile(data: ByteArray, path: String, host: SSHHostID) {
            sent = data.decodeToString()
        }
        override suspend fun homeDirectory(host: SSHHostID) = "/home/anna"
        override suspend fun listDirectory(path: String, host: SSHHostID) = emptyList<RemoteFileEntry>()
        override suspend fun downloadFile(path: String, host: SSHHostID, maxBytes: Long) = ByteArray(0)
        override suspend fun deleteFile(entry: RemoteFileEntry, host: SSHHostID) = Unit

        override fun stream(command: String, host: SSHHostID, timeout: Duration): Flow<ExecChunk> = emptyFlow()
        override suspend fun fireAndForget(command: String, host: SSHHostID) = Unit
        override suspend fun disconnect() { disconnects += 1 }
    }

    private class ScriptedInstaller(private val events: List<SetupEvent>, private val fail: Throwable? = null) {
        data class Ran(
            val requested: String,
            val actual: String,
            val skipDNSCheck: Boolean,
            val skipServices: Boolean,
        )

        val ran = mutableListOf<Ran>()

        fun installing(target: InstallTarget) = InstallViewModel.Installing { script, file, skip, skipServices ->
            ran += Ran(target.script.fileName, file, skip, skipServices)
            flow {
                for (event in events) emit(event)
                fail?.let { throw it }
            }
        }
    }

    private fun model(
        scope: CoroutineScope,
        bundle: GeneratedBundle = singleHostBundle(),
        deployment: Deployment = server(),
        runner: SSHCommandRunner = ProbeRunner(),
        installing: (SSHCommandRunner, InstallTarget) -> InstallViewModel.Installing =
            { _, _ -> InstallViewModel.Installing { _, _, _, _ -> emptyFlow() } },
        saveReport: (String, String) -> Unit = { _, _ -> },
        appPublicKey: String? = "ssh-ed25519 AAAAC3Nz test",
    ) = InstallViewModel(
        scope = scope,
        deployment = deployment,
        bundle = bundle,
        appPublicKey = appPublicKey,
        runners = { runner },
        installers = installing,
        browsers = { it as? RemoteFileBrowser },
        sleeper = {},
        saveReport = saveReport,
    )

    // -------------------------------------------------------------- Targets

    @Test
    fun `a single host install has one target at the recorded address`() = runTest {
        val model = model(this)
        val targets = model.state.value.targets

        assertEquals(1, targets.size)
        assertEquals(InstallTarget.Kind.SINGLE, targets[0].kind)
        assertEquals("203.0.113.10", targets[0].address)
        assertEquals("root", targets[0].username, "the script runs as the install account")
    }

    @Test
    fun `a pair installs the relay first and asks for the home address`() = runTest {
        val model = model(this, bundle = pairBundle(), deployment = server(Topology.VPS_RELAY_WITH_HOME_BACKEND))
        val targets = model.state.value.targets

        assertEquals(listOf(InstallTarget.Kind.VPS, InstallTarget.Kind.HOME), targets.map { it.kind })
        assertEquals("203.0.113.10", targets[0].address)
        assertEquals("", targets[1].address)
    }

    @Test
    fun `each half knows the distribution its own script was built for`() = runTest {
        val model = model(this, bundle = pairBundle(), deployment = server(Topology.VPS_RELAY_WITH_HOME_BACKEND))
        assertEquals("debian", model.state.value.targets[0].expectedDistribution)
        assertEquals("ubuntu", model.state.value.targets[1].expectedDistribution)
    }

    // ---------------------------------------------------- Connection checks

    /** Nothing starts until every machine has answered */
    @Test
    fun `the install cannot start before the machines answer`() = runTest {
        val model = model(this)
        assertFalse(model.state.value.canStart)

        model.check(DeploymentNode.LegacySlot.VPS)
        runCurrent()

        assertIs<InstallTarget.Connection.Ok>(model.state.value.targets[0].connection)
        assertTrue(model.state.value.canStart)
    }

    /** The probe asks both questions in ONE login */
    @Test
    fun `the probe asks who you are and what you are in one command`() = runTest {
        val runner = ProbeRunner()
        val model = model(this, runner = runner)
        model.check(DeploymentNode.LegacySlot.VPS)
        runCurrent()

        assertEquals(1, runner.attempts)
        val command = runner.commands.single()
        assertTrue("GRYONIXNEXUS_PING" in command)
        assertTrue("/etc/os-release" in command)
        assertEquals(1, runner.disconnects, "the probe's session was left open")
    }

    @Test
    fun `a non-root sign-in without passwordless sudo asks for the password`() = runTest {
        val runner = ProbeRunner(sudoReady = false)
        val model = model(this, runner = runner)
        model.edit(DeploymentNode.LegacySlot.VPS) { it.copy(username = "anna") }
        model.check(DeploymentNode.LegacySlot.VPS)
        runCurrent()
        assertIs<InstallTarget.Connection.NeedsSudoPassword>(model.state.value.targets[0].connection)
        assertFalse(model.state.value.canStart)

        model.grantSudo(DeploymentNode.LegacySlot.VPS, "wrong")
        runCurrent()
        assertEquals(
            InstallTarget.Connection.NeedsSudoPassword(SudoProblem.WrongPassword),
            model.state.value.targets[0].connection,
        )

        model.grantSudo(DeploymentNode.LegacySlot.VPS, "right")
        runCurrent()
        assertIs<InstallTarget.Connection.Ok>(model.state.value.targets[0].connection)
        assertFalse(runner.commands.any { "right" in it || "wrong" in it })
    }

    @Test
    fun `a refusal is retried before it is reported`() = runTest {
        val runner = ProbeRunner(fails = 2)
        val model = model(this, runner = runner)
        model.check(DeploymentNode.LegacySlot.VPS)
        runCurrent()

        assertEquals(3, runner.attempts)
        assertIs<InstallTarget.Connection.Ok>(model.state.value.targets[0].connection)
    }

    @Test
    fun `a machine that never answers reports the reason`() = runTest {
        val model = model(this, runner = ProbeRunner(fails = 99))
        model.check(DeploymentNode.LegacySlot.VPS)
        runCurrent()

        val connection = model.state.value.targets[0].connection
        assertIs<InstallTarget.Connection.Failed>(connection)
        assertTrue("connection refused" in connection.reason)
        assertFalse(model.state.value.canStart)
    }

    /** The wrong distribution is caught BEFORE the script runs */
    @Test
    fun `a machine of the wrong distribution is refused with both names`() = runTest {
        val model = model(this, runner = ProbeRunner(id = "fedora"))
        model.check(DeploymentNode.LegacySlot.VPS)
        runCurrent()

        val connection = model.state.value.targets[0].connection
        assertIs<InstallTarget.Connection.Failed>(connection)
        assertTrue("fedora" in connection.reason, "the host's own answer is missing")
        assertTrue("debian" in connection.reason, "what the script expects is missing")
    }

    @Test
    fun `a derivative that names its base is accepted`() = runTest {
        val model = model(this, runner = ProbeRunner(id = "devuan", idLike = "debian"))
        model.check(DeploymentNode.LegacySlot.VPS)
        runCurrent()

        assertIs<InstallTarget.Connection.Ok>(model.state.value.targets[0].connection)
    }

    /** A script that names no distribution blocks nothing */
    @Test
    fun `a script without the marker does not judge the machine`() = runTest {
        val bundle = GeneratedBundle(artifacts = listOf(script(ServerRole.SINGLE_HOST, distribution = null)))
        val model = model(this, bundle = bundle, runner = ProbeRunner(id = "fedora"))
        model.check(DeploymentNode.LegacySlot.VPS)
        runCurrent()

        assertIs<InstallTarget.Connection.Ok>(model.state.value.targets[0].connection)
    }

    @Test
    fun `editing where or as whom invalidates the check`() = runTest {
        val model = model(this)
        model.check(DeploymentNode.LegacySlot.VPS)
        runCurrent()
        assertTrue(model.state.value.canStart)

        model.edit(DeploymentNode.LegacySlot.VPS) { it.copy(address = "203.0.113.99") }

        assertIs<InstallTarget.Connection.Unchecked>(model.state.value.targets[0].connection)
        assertFalse(model.state.value.canStart)
    }

    @Test
    fun `an edit that changes nothing keeps the answer`() = runTest {
        val model = model(this)
        model.check(DeploymentNode.LegacySlot.VPS)
        runCurrent()

        model.edit(DeploymentNode.LegacySlot.VPS) { it }

        assertIs<InstallTarget.Connection.Ok>(model.state.value.targets[0].connection)
    }

    // ------------------------------------------------------------- Running

    private suspend fun readyModel(
        scope: CoroutineScope,
        bundle: GeneratedBundle,
        deployment: Deployment,
        saveReport: (String, String) -> Unit = { _, _ -> },
        installing: (SSHCommandRunner, InstallTarget) -> InstallViewModel.Installing,
    ): InstallViewModel {
        val model = model(
            scope,
            bundle = bundle,
            deployment = deployment,
            installing = installing,
            saveReport = saveReport,
        )
        for (target in model.state.value.targets) {
            model.edit(target.slot) { it.copy(address = "203.0.113.20") }
            model.check(target.slot)
        }
        return model
    }

    @Test
    fun `a clean run ends finished`() = runTest {
        val installer = ScriptedInstaller(listOf(SetupEvent.Stage("Firewall"), SetupEvent.Done))
        val model = readyModel(this, singleHostBundle(), server()) { _, target -> installer.installing(target) }
        runCurrent()
        model.start()
        runCurrent()

        assertIs<InstallState.Phase.Finished>(model.state.value.phase)
        assertEquals("Firewall", model.state.value.stage)
    }

    @Test
    fun `a retry resumes at the machine that failed`() = runTest {
        val runs = mutableListOf<String>()
        val model = readyModel(
            this,
            pairBundle(homeDistribution = "debian"),
            server(Topology.VPS_RELAY_WITH_HOME_BACKEND),
        ) { _, target ->
            InstallViewModel.Installing { _, fileName, _, _ ->
                runs += fileName
                flow {
                    emit(SetupEvent.Done)
                    if (target.kind == InstallTarget.Kind.HOME && runs.count { "home" in it } == 1) {
                        throw IllegalStateException("home half refused")
                    }
                }
            }
        }
        runCurrent()
        model.start()
        runCurrent()

        assertIs<InstallState.Phase.Failed>(model.state.value.phase)
        assertEquals(1, model.state.value.currentTarget, "the relay was not counted as done")

        model.retry()
        runCurrent()

        assertIs<InstallState.Phase.Finished>(model.state.value.phase)
        assertEquals(
            listOf("setup-vps_relay.sh", "setup-home_backend.sh", "setup-home_backend.sh"),
            runs,
            "the relay was installed a second time"
        )
    }

    /** The DNS marker is a state, not a log line */
    @Test
    fun `the dns marker sets the state and stays out of the log`() = runTest {
        val installer = ScriptedInstaller(
            listOf(
                SetupEvent.Line(SetupMarkers.DNS_CHECK_FAILED),
                SetupEvent.Line("A record for mail.example.com not found"),
            ),
            fail = IllegalStateException("script failed"),
        )
        val model = readyModel(this, singleHostBundle(), server()) { _, target -> installer.installing(target) }
        runCurrent()
        model.start()
        runCurrent()

        assertTrue(model.state.value.sawDNSCheckFailure)
        assertFalse(model.state.value.sawPortConflict)
        assertTrue(model.state.value.log.none { SetupMarkers.DNS_CHECK_FAILED in it })
        assertTrue(model.state.value.log.any { "A record" in it }, "the explanation was swallowed too")
    }

    @Test
    fun `the port marker sets its own state`() = runTest {
        val installer = ScriptedInstaller(
            listOf(
                SetupEvent.Line(SetupMarkers.PORTS_IN_USE),
                SetupEvent.Line("port 53 is held by pihole"),
            ),
            fail = IllegalStateException("script failed"),
        )
        val model = readyModel(this, singleHostBundle(), server()) { _, target -> installer.installing(target) }
        runCurrent()
        model.start()
        runCurrent()

        assertTrue(model.state.value.sawPortConflict)
        assertFalse(model.state.value.sawDNSCheckFailure)
        assertTrue(model.state.value.log.none { SetupMarkers.PORTS_IN_USE in it })
    }

    @Test
    fun `skipping the dns check applies to that retry alone`() = runTest {
        val asked = mutableListOf<Boolean>()
        var failNext = true
        val model = readyModel(this, singleHostBundle(), server()) { _, _ ->
            InstallViewModel.Installing { _, _, skip, _ ->
                asked += skip
                flow {
                    emit(SetupEvent.Done)
                    if (failNext) throw IllegalStateException("script failed")
                }
            }
        }
        runCurrent()
        model.start()
        runCurrent()
        assertIs<InstallState.Phase.Failed>(model.state.value.phase)

        model.retry(skipDNSCheck = true)
        runCurrent()
        assertIs<InstallState.Phase.Failed>(model.state.value.phase)

        failNext = false
        model.retry()
        runCurrent()

        assertEquals(listOf(false, true, false), asked)
    }

    @Test
    fun `a skipped dns check does not carry into a later run`() = runTest {
        val asked = mutableListOf<Boolean>()
        var attempt = 0
        val model = readyModel(this, singleHostBundle(), server()) { _, _ ->
            InstallViewModel.Installing { _, _, skip, _ ->
                asked += skip
                attempt += 1
                when (attempt) {
                    1 -> flow { throw IllegalStateException("script failed") }
                    2 -> flow { awaitCancellation() }
                    else -> flow { emit(SetupEvent.Done) }
                }
            }
        }
        runCurrent()
        model.start()
        runCurrent()
        assertIs<InstallState.Phase.Failed>(model.state.value.phase)

        model.retry(skipDNSCheck = true)
        runCurrent()
        assertTrue(model.state.value.isInstalling)

        model.stopFollowing()
        runCurrent()
        model.start()
        runCurrent()

        assertEquals(listOf(false, true, false), asked, "the skip outlived the run that asked for it")
        assertIs<InstallState.Phase.Finished>(model.state.value.phase)
    }

    @Test
    fun `losing the log says so instead of going quiet`() = runTest {
        val installer = ScriptedInstaller(listOf(SetupEvent.Reconnecting(2), SetupEvent.Done))
        val model = readyModel(this, singleHostBundle(), server()) { _, target -> installer.installing(target) }
        runCurrent()
        model.start()
        runCurrent()

        assertTrue("attempt 2" in model.state.value.stage)
        assertTrue(model.state.value.log.any { "keeps running on the server" in it })
    }

    /** The report is kept, and it is kept per machine */
    @Test
    fun `each machines report is kept with the machine it came from`() = runTest {
        val model = readyModel(
            this,
            pairBundle(homeDistribution = "debian"),
            server(Topology.VPS_RELAY_WITH_HOME_BACKEND),
        ) { _, target ->
            InstallViewModel.Installing { _, _, _, _ ->
                flow {
                    emit(SetupEvent.Report("report for ${target.kind}"))
                    emit(SetupEvent.Done)
                }
            }
        }
        runCurrent()
        model.start()
        runCurrent()

        assertEquals(
            listOf(InstallTarget.Kind.VPS, InstallTarget.Kind.HOME),
            model.state.value.reports.map { it.kind }
        )
    }

    @Test
    fun `a machines report is stored before the run that follows it can fail`() = runTest {
        val saved = mutableListOf<Pair<String, String>>()
        val model = readyModel(
            this,
            pairBundle(homeDistribution = "debian"),
            server(Topology.VPS_RELAY_WITH_HOME_BACKEND),
            saveReport = { host, text -> saved += host to text },
        ) { _, target ->
            InstallViewModel.Installing { _, _, _, _ ->
                flow {
                    emit(SetupEvent.Report("report for ${target.kind}"))
                    if (target.kind == InstallTarget.Kind.HOME) {
                        throw IllegalStateException("the home half died")
                    }
                    emit(SetupEvent.Done)
                }
            }
        }
        runCurrent()
        model.start()
        runCurrent()

        assertIs<InstallState.Phase.Failed>(model.state.value.phase)
        assertEquals(listOf("vps", "home"), saved.map { it.first })
        assertEquals("report for VPS", saved.first().second)
    }

    @Test
    fun `the log keeps every line of a long install`() = runTest {
        val installer = ScriptedInstaller((1..900).map { SetupEvent.Line("line $it") } + SetupEvent.Done)
        val model = readyModel(this, singleHostBundle(), server()) { _, target -> installer.installing(target) }
        runCurrent()
        model.start()
        runCurrent()

        assertEquals(900, model.state.value.log.size)
        assertEquals("line 1", model.state.value.log.first())
        assertEquals("line 900", model.state.value.log.last())
    }

    @Test
    fun `the failure shown to the owner has the markers taken out`() = runTest {
        val model = readyModel(this, singleHostBundle(), server()) { _, _ ->
            InstallViewModel.Installing { _, _, _, _ ->
                flow {
                    throw IllegalStateException(
                        "Command failed (exit 1): install\n${SetupMarkers.PORTS_IN_USE}\n" +
                            "ERROR: port 53/tcp is already used by «adguardhome»\n" +
                            "${SetupProgressParser.EXIT_MARKER}1"
                    )
                }
            }
        }
        runCurrent()
        model.start()
        runCurrent()

        val phase = model.state.value.phase
        assertIs<InstallState.Phase.Failed>(phase)
        assertFalse("GRYONIXNEXUS" in phase.reason, "a protocol token is on screen: ${phase.reason}")
        assertTrue(
            "port 53/tcp is already used by «adguardhome»" in phase.reason,
            "and the part the owner acts on was thrown away with it"
        )
    }

    /** The grant step disappears when nothing is granted */
    @Test
    fun `a password login needs no access grant`() = runTest {
        val model = model(this)
        assertTrue(model.state.value.needsAccessGrant)

        model.edit(DeploymentNode.LegacySlot.VPS) {
            it.copy(secret = InstallTarget.Secret.Password("hunter2"))
        }

        assertFalse(model.state.value.needsAccessGrant)
        assertTrue(model.grantCommand.isNotEmpty(), "the command itself still exists for the other case")
    }

    @Test
    fun `the bare key is offered only when there is one`() = runTest {
        assertEquals("ssh-ed25519 AAAAC3Nz test", model(this).publicKey)
        assertNull(model(this, appPublicKey = null).publicKey)
        assertNull(model(this, appPublicKey = "").publicKey)
        assertTrue(
            model(this, appPublicKey = "").grantCommand.isNotEmpty(),
            "the command is still built: an empty key is not an empty command",
        )
    }
}
