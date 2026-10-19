package com.skaymer.gryonixnexus.app.install

import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.notify.OperationNotice
import com.skaymer.gryonixnexus.app.notify.OperationKind
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import com.skaymer.gryonixnexus.app.servers.ServiceInstallPlan
import com.skaymer.gryonixnexus.agentcontrol.AgentDkimOperations
import com.skaymer.gryonixnexus.agentcontrol.AgentInstallContext
import com.skaymer.gryonixnexus.agentcontrol.AgentInstallSettings
import com.skaymer.gryonixnexus.agentcontrol.AgentInstallOperations
import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.agentcontrol.AgentPlanPurpose
import com.skaymer.gryonixnexus.agentcontrol.AgentInstallPlan
import com.skaymer.gryonixnexus.agentcontrol.AgentChannelGate
import com.skaymer.gryonixnexus.agentclient.AgentClient
import com.skaymer.gryonixnexus.app.agent.AgentBootstrapOperations
import com.skaymer.gryonixnexus.app.access.SudoProblem
import com.skaymer.gryonixnexus.app.agent.AgentSessions
import com.skaymer.gryonixnexus.app.servers.TunnelSetup
import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServerRequirements
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.catalog.storage.SwapPlan
import com.skaymer.gryonixnexus.catalog.storage.ServerHardware
import com.skaymer.gryonixnexus.core.Artifact
import com.skaymer.gryonixnexus.core.ArtifactKind
import com.skaymer.gryonixnexus.core.DistributionMatch
import com.skaymer.gryonixnexus.core.GeneratedBundle
import com.skaymer.gryonixnexus.core.ServerRole
import com.skaymer.gryonixnexus.recipe.DashboardAccessInput
import com.skaymer.gryonixnexus.recipe.MailRecipe
import com.skaymer.gryonixnexus.recipe.SetupMarkers
import com.skaymer.gryonixnexus.servercontrol.AccessGrantCommand
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.DeploymentNode
import com.skaymer.gryonixnexus.servercontrol.RemoteFileBrowser
import com.skaymer.gryonixnexus.servercontrol.SSHCommandRunner
import com.skaymer.gryonixnexus.servercontrol.SSHHostID
import com.skaymer.gryonixnexus.servercontrol.ServerControlError
import com.skaymer.gryonixnexus.servercontrol.SetupEvent
import com.skaymer.gryonixnexus.servercontrol.SetupInstaller
import com.skaymer.gryonixnexus.servercontrol.SudoAccess
import com.skaymer.gryonixnexus.transport.SSHJCommandRunner
import com.skaymer.gryonixnexus.transport.SSHJFileBrowser
import gryonixnexusd.v1.HostRole
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Everything the install screen draws, in one value */
data class InstallState(
    val targets: List<InstallTarget> = emptyList(),
    val phase: Phase = Phase.Setup,
    val currentTarget: Int = 0,
    val stage: String = "",
    val stepIndex: Int = 0,
    val stepTotal: Int = 0,
    /** One machine's run, as one bar */
    val parts: InstallParts = InstallParts(),
    val log: List<String> = emptyList(),
    val reports: List<Report> = emptyList(),
    val installWarnings: List<String> = emptyList(),
    /** The script stopped on its early A-record probe */
    val sawDNSCheckFailure: Boolean = false,
    val sawPortConflict: Boolean = false,
) {
    val isInstalling: Boolean get() = phase is Phase.Installing

    /** Every machine answered, and each carries a way in */
    val canStart: Boolean
        get() = phase is Phase.Setup && targets.isNotEmpty() && targets.all { it.isReady }

    val needsAccessGrant: Boolean
        get() = targets.any { it.secret is InstallTarget.Secret.AppKey }

    val progress: Double
        get() {
            if (targets.isEmpty()) return 0.0
            val script = if (stepTotal > 0) stepIndex.toDouble() / stepTotal else 0.0
            return (currentTarget + parts.fraction(script)) / targets.size
        }

    data class Report(val kind: InstallTarget.Kind, val text: String)

    sealed interface Phase {
        /** Addresses, credentials, connection checks */
        data object Setup : Phase
        data object Installing : Phase
        data object Finished : Phase
        data class Failed(val reason: String) : Phase
    }
}

class InstallViewModel(
    private val scope: CoroutineScope,
    private val deployment: Deployment,
    private val bundle: GeneratedBundle,
    private val appPublicKey: String?,
    private val runners: (InstallTarget) -> SSHCommandRunner,
    /** Injected so the rules can be driven without a server */
    private val installers: (SSHCommandRunner, InstallTarget) -> Installing =
        { runner, target ->
            val ported = SetupInstaller(
                runner = runner,
                host = SSHHostID.VPS,
                username = target.username.trim(),
            )
            Installing { script, fileName, skipDNSCheck, skipServices ->
                ported.install(script, fileName, skipDNSCheck, skipServices)
            }
        },
    /** Injected so the connection-check backoff does not make tests wait */
    private val sleeper: suspend (Duration) -> Unit = { delay(it) },
    /** Where a finished machine's report is KEPT */
    private val saveReport: (host: String, text: String) -> Unit = { _, _ -> },
    private val agentSessions: AgentSessions? = null,
    /** The agent's own source archive — see `AgentBootstrapOperations.Sources` */
    private val agentSources: AgentBootstrapOperations.Sources? = null,
    private val agentContext: ((Deployment) -> AgentInstallContext)? = null,
    private val persistUsesAgent: (Deployment) -> Unit = {},
    /** The SFTP half, which carries the sudo password */
    private val browsers: (SSHCommandRunner) -> RemoteFileBrowser? =
        { runner -> (runner as? SSHJCommandRunner)?.let(::SSHJFileBrowser) },
    /** The local server's address from the configurator */
    private val homeAddress: String = "",
    /** Mints the tunnel's connector token and publishes its names */
    private val tunnel: TunnelSetup? = null,
) {
    fun interface Installing {
        fun install(
            script: String,
            fileName: String,
            skipDNSCheck: Boolean,
            skipServices: Boolean,
        ): Flow<SetupEvent>
    }

    private val _state = MutableStateFlow(InstallState(targets = initialTargets()))
    val state: StateFlow<InstallState> = _state.asStateFlow()

    private var job: Job? = null

    private var skipDNSCheck = false
    private var tunnelConnected = false

    val dnsRecords: String? =
        bundle.artifacts.firstOrNull { it.kind == ArtifactKind.DNS_RECORD }?.contents

    val grantCommand: String get() = AccessGrantCommand.command(appPublicKey.orEmpty())

    /** The bare public half */
    val publicKey: String? get() = appPublicKey?.takeIf { it.isNotEmpty() }

    private fun initialTargets(): List<InstallTarget> {
        fun script(role: ServerRole): Artifact? = bundle.artifacts.firstOrNull {
            it.kind == ArtifactKind.SHELL_SCRIPT && it.server == role
        }
        script(ServerRole.SINGLE_HOST)?.let { single ->
            return listOf(
                InstallTarget(
                    kind = InstallTarget.Kind.SINGLE,
                    script = single,
                    slot = DeploymentNode.LegacySlot.VPS,
                    address = deployment.entry.host,
                    port = deployment.entry.port,
                )
            )
        }
        val relay = script(ServerRole.VPS_RELAY) ?: return emptyList()
        val home = script(ServerRole.HOME_BACKEND) ?: return emptyList()
        return listOf(
            InstallTarget(
                kind = InstallTarget.Kind.VPS,
                script = relay,
                slot = DeploymentNode.LegacySlot.VPS,
                address = deployment.entry.host,
                port = deployment.entry.port,
            ),
            InstallTarget(
                kind = InstallTarget.Kind.HOME,
                script = home,
                slot = DeploymentNode.LegacySlot.HOME,
                address = homeAddress,
            ),
        )
    }

    /** What the chosen services need from a server */
    val requirements: ServerRequirements get() = ServiceRegistry.requirements(deployment.services)

    /** A relay carries no services, so it needs far less */
    fun requirements(kind: InstallTarget.Kind): ServerRequirements =
        if (kind == InstallTarget.Kind.VPS) ServiceRegistry.relayRequirements else requirements

    /** Makes a swap file, then reads the machine again */
    fun addSwap(slot: DeploymentNode.LegacySlot, sizeGB: Int) {
        val target = _state.value.targets.firstOrNull { it.slot == slot } ?: return
        edit(slot) { it.copy(swap = InstallTarget.Swap.Adding) }
        scope.launch {
            val outcome = try {
                val plan = SwapPlan(sizeGB)
                StoragePreparation.run(StorageStep(StorageStep.Kind.SWAP, plan.script(), SwapPlan.DONE_MARKER),
                    runners(target), target.username.trim())
                InstallTarget.Swap.Idle
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                InstallTarget.Swap.Failed(describe(failure))
            }
            edit(slot) { it.copy(swap = outcome) }
            if (outcome == InstallTarget.Swap.Idle) check(slot)
        }
    }

    // ------------------------------------------------------------ Editing

    fun edit(slot: DeploymentNode.LegacySlot, transform: (InstallTarget) -> InstallTarget) {
        _state.value = _state.value.copy(
            targets = _state.value.targets.map { target ->
                if (target.slot != slot) target else transform(target).let {
                    if (it.address != target.address ||
                        it.username != target.username ||
                        it.port != target.port ||
                        it.secret != target.secret
                    ) {
                        it.copy(
                            connection = InstallTarget.Connection.Unchecked,
                            hardware = null,
                            storage = StorageChoice(),
                        )
                    } else {
                        it
                    }
                }
            }
        )
    }

    // --------------------------------------------------- Connection check

    fun check(slot: DeploymentNode.LegacySlot) {
        val target = _state.value.targets.firstOrNull { it.slot == slot } ?: return
        edit(slot) { it.copy(connection = InstallTarget.Connection.Checking) }
        scope.launch {
            val (verdict, hardware) = probe(target)
            edit(slot) {
                if (it.hardware == hardware) it.copy(connection = verdict)
                else it.copy(connection = verdict, hardware = hardware,
                    storage = hardware?.let(StorageChoice::defaults) ?: StorageChoice())
            }
        }
    }

    private suspend fun probe(target: InstallTarget): Pair<InstallTarget.Connection, ServerHardware?> {
        var lastError = "the server did not answer"
        repeat(PROBE_ATTEMPTS) { attempt ->
            if (attempt > 0) sleeper(PROBE_BACKOFF)
            try {
                val runner = runners(target)
                val result = runner.run(PROBE_COMMAND, SSHHostID.VPS, PROBE_TIMEOUT)
                runner.disconnect()
                if (PROBE_TOKEN in result.stdout) {
                    val hardware = ServerHardware.parse(result.stdout)
                    val mismatch = distributionMismatch(target, result.stdout)
                    val verdict = when {
                        mismatch != null -> InstallTarget.Connection.Failed(mismatch)
                        target.username.trim() != "root" && !SudoAccess.isReady(result.stdout) ->
                            InstallTarget.Connection.NeedsSudoPassword()
                        else -> InstallTarget.Connection.Ok
                    }
                    return verdict to hardware
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                lastError = describe(failure)
            }
        }
        return InstallTarget.Connection.Failed(lastError) to null
    }

    /** Writes passwordless sudo with the password typed once */
    fun grantSudo(slot: DeploymentNode.LegacySlot, password: String) {
        val target = _state.value.targets.firstOrNull { it.slot == slot } ?: return
        edit(slot) { it.copy(connection = InstallTarget.Connection.Checking) }
        scope.launch {
            val verdict = sudoVerdict(target, password)
            if (verdict is InstallTarget.Connection.Ok) check(slot) else edit(slot) { it.copy(connection = verdict) }
        }
    }

    private suspend fun sudoVerdict(target: InstallTarget, password: String): InstallTarget.Connection {
        val runner = runners(target)
        return try {
            val files = browsers(runner)
                ?: return InstallTarget.Connection.Failed("This session cannot send files.")
            connection(SudoAccess.grant(password, runner, files, SSHHostID.VPS))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            InstallTarget.Connection.NeedsSudoPassword(SudoProblem.Failed(describe(failure)))
        } finally {
            runner.disconnect()
        }
    }

    private fun connection(outcome: SudoAccess.Outcome): InstallTarget.Connection = when (outcome) {
        SudoAccess.Outcome.Granted -> InstallTarget.Connection.Ok
        SudoAccess.Outcome.WrongPassword -> InstallTarget.Connection.NeedsSudoPassword(SudoProblem.WrongPassword)
        SudoAccess.Outcome.NotAllowed -> InstallTarget.Connection.NotAdministrator
        is SudoAccess.Outcome.Failed ->
            InstallTarget.Connection.NeedsSudoPassword(SudoProblem.Failed(outcome.detail))
    }

    private fun distributionMismatch(target: InstallTarget, output: String): String? {
        val expected = target.expectedDistribution ?: return null
        val line = output.lineSequence()
            .firstOrNull { it.startsWith("${SetupMarkers.DISTRIBUTION}:") } ?: return null
        val fields = line.split(":")
        val id = fields.getOrNull(1).orEmpty()
        val idLike = fields.getOrNull(2).orEmpty()
        if (id.isEmpty()) return null
        if (DistributionMatch.accepts(expected = expected, id = id, idLike = idLike)) return null
        return "This machine reports $id, but its script was generated for $expected. " +
            "Go back to the configuration, set this host's distribution, and generate again."
    }

    private fun describe(failure: Throwable): String {
        val text = InstallFailureText.readable(
            failure.message ?: failure::class.simpleName.orEmpty()
        )
        if (text.contains("auth", ignoreCase = true)) {
            return "The server refused the app's key. Run the command from step 1 on this " +
                "machine and check the account it prints — it must be the install account " +
                "above. A key added for a different account, or a ~/.ssh left owned by root, " +
                "both look exactly like this."
        }
        return text
    }

    // --------------------------------------------------------- Installing

    fun start() {
        if (!_state.value.canStart) return
        _state.value = _state.value.copy(phase = InstallState.Phase.Installing)
        run()
    }

    /** Resumes at the machine that failed */
    fun retry(skipDNSCheck: Boolean = false) {
        if (_state.value.phase !is InstallState.Phase.Failed) return
        this.skipDNSCheck = skipDNSCheck
        _state.value = _state.value.copy(phase = InstallState.Phase.Installing)
        run()
    }

    fun stopFollowing() {
        job?.cancel()
        job = null
        if (_state.value.isInstalling) {
            _state.value = _state.value.copy(phase = InstallState.Phase.Setup)
        }
    }

    private fun run() {
        job?.cancel()
        job = scope.launch {
            val notice = OperationNotices.start(R.string.notice_installing_server, server = deployment.name, kind = OperationKind.INSTALL)
            val follower = launch { _state.collect { notice.update(it.stage) } }
            try {
                while (_state.value.currentTarget < _state.value.targets.size) {
                    val target = _state.value.targets[_state.value.currentTarget]
                    try {
                        install(target)
                    } catch (cancelled: CancellationException) {
                        _state.value = _state.value.copy(phase = InstallState.Phase.Setup)
                        throw cancelled
                    } catch (failure: Exception) {
                        _state.value = _state.value.copy(
                            phase = InstallState.Phase.Failed(describe(failure))
                        )
                        return@launch
                    }
                    _state.value = _state.value.copy(currentTarget = _state.value.currentTarget + 1)
                }
                _state.value = _state.value.copy(phase = InstallState.Phase.Finished)
            } finally {
                skipDNSCheck = false
                follower.cancel()
                finishNotice(notice)
            }
        }
    }

    private fun finishNotice(notice: OperationNotice) {
        when (val phase = _state.value.phase) {
            InstallState.Phase.Finished -> notice.finish(OperationNotices.text(R.string.notice_done))
            is InstallState.Phase.Failed -> notice.finish("", phase.reason)
            else -> notice.finish(OperationNotices.text(R.string.notice_continues))
        }
    }

    /** Builds the chosen RAID and fast storage before setup */
    private suspend fun prepareStorage(target: InstallTarget, runner: SSHCommandRunner) {
        for (step in target.storageSteps) {
            val title = when (step.kind) {
                StorageStep.Kind.IMPORT -> "Bringing back the ${step.name} array…"
                StorageStep.Kind.MIRROR -> "Mirroring the cache disks…"
                StorageStep.Kind.RAID -> "Building the RAID array…"
                StorageStep.Kind.CACHE -> "Preparing the cache disk…"
                StorageStep.Kind.HEALTH -> "Reading the disks…"
                StorageStep.Kind.CHANGE -> "Changing the disks…"
                StorageStep.Kind.SWAP -> "Adding swap…"
            }
            _state.value = _state.value.copy(stage = title, log = _state.value.log + title)
            StoragePreparation.run(step, runner, target.username.trim())
        }
    }

    private suspend fun install(target: InstallTarget) {
        _state.value = _state.value.copy(
            stage = "",
            stepIndex = 0,
            stepTotal = 0,
            sawDNSCheckFailure = false,
            sawPortConflict = false,
        )
        val routeThroughAgent = canRouteThroughAgent()
        updateParts { InstallParts(throughAgent = routeThroughAgent) }
        val runner = runners(target)
        try {
            prepareStorage(target, runner)
            val oneByOne = serviceScripts(target).isNotEmpty()
            installers(runner, target)
                .install(
                    target.script.contents, target.script.fileName,
                    skipDNSCheck, routeThroughAgent || oneByOne,
                )
                .collect { event -> handle(event, target) }

            if (!routeThroughAgent) {
                if (oneByOne) installOneByOne(target, runner)
                return
            }
            updateParts { it.copy(scriptDone = true) }

            for (attempt in 1..AGENT_ATTEMPTS) {
                try {
                    installViaAgent(target, runner)
                    return
                } catch (cancelled: CancellationException) {
                    throw cancelled
                } catch (failure: Exception) {
                    appendLog("Why: ${failure.message ?: failure::class.simpleName}")
                    if (agentPlanStarted) throw failure
                    if (attempt == AGENT_ATTEMPTS) break
                    val retry = "The agent step did not finish. Trying it once more…"
                    _state.value = _state.value.copy(stage = retry)
                    appendLog(retry)
                    delay(3_000)
                }
            }
            val note = "Could not hand services to the agent — installing them directly instead…"
            _state.value = _state.value.copy(stage = note)
            appendLog(note)
            installOneByOne(target, runner)
            revokeInstallKey(runner)
        } finally {
            runner.disconnect()
        }
    }

    /** This machine's service scripts, the finishing one last */
    private fun serviceScripts(target: InstallTarget): List<Artifact> =
        bundle.serviceScripts.filter { it.server == target.script.server }

    /** Each service by its own script, failures collected */
    private suspend fun installOneByOne(target: InstallTarget, runner: SSHCommandRunner) {
        updateParts { it.copy(directServices = true) }
        val scripts = serviceScripts(target)
        val failed = mutableListOf<String>()
        for ((index, script) in scripts.withIndex()) {
            if (script.fileName == Artifact.FINISH_SETUP_NAME && failed.isNotEmpty()) break
            val stage = "Installing ${script.summary} (${index + 1} of ${scripts.size})…"
            _state.value = _state.value.copy(stage = stage)
            appendLog(stage)
            try {
                runServiceScript(script, index, scripts.size, target, runner)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                failed += script.summary
                appendLog("Why: ${failure.message ?: failure::class.simpleName}")
            }
        }
        if (failed.isNotEmpty()) {
            throw IllegalStateException("Not installed: ${failed.joinToString(", ")}. Start the installation again to retry them.")
        }
    }

    private suspend fun runServiceScript(script: Artifact, index: Int, count: Int, target: InstallTarget,
                                         runner: SSHCommandRunner) {
        installers(runner, target).install(script.contents, script.fileName, true, false).collect { event ->
            if (event is SetupEvent.Step) {
                val step = event.index.toDouble() / maxOf(event.total, 1)
                updateParts { it.copy(directStep = (index + step) / count) }
            } else {
                handle(event, target)
            }
        }
    }

    private fun canRouteThroughAgent(): Boolean =
        agentSessions != null && agentSources != null && agentContext != null &&
            deployment.entry.user.trim().isNotEmpty()

    private suspend fun installViaAgent(target: InstallTarget, runner: SSHCommandRunner) {
        val sources = agentSources ?: return
        val sessions = agentSessions ?: return
        val contextOf = agentContext ?: return
        val jvmRunner = runner as? SSHJCommandRunner
            ?: throw ServerControlError.NotConfigured("This session cannot reach the agent.")

        _state.value = _state.value.copy(stage = "Preparing the server…")
        AgentBootstrapOperations.install(
            runner = jvmRunner,
            files = SSHJFileBrowser(jvmRunner),
            host = SSHHostID.VPS,
            sources = sources,
            onPhase = { line -> _state.value = _state.value.copy(stage = line) },
            onOutput = { line ->
                appendLog(line)
                updateParts { it.copy(agentLines = it.agentLines + 1) }
            },
        )
        updateParts { it.copy(agentDone = true) }

        val client = sessions.client(jvmRunner, SSHHostID.VPS)
        client.getState().agent_version
        persistUsesAgent(deployment)

        val gate = sessions.gate(deployment)
        if (target.kind == InstallTarget.Kind.VPS && deployment.hasRelayIngress) {
            _state.value = _state.value.copy(stage = "Configuring the relay…")
            val context = contextOf(deployment).let {
                it.copy(host = it.host.copy(role = HostRole.HOST_ROLE_VPS_RELAY))
            }
            AgentInstallOperations(client, gate).provisionHost(context)
            revokeInstallKey(jvmRunner)
            return
        }

        val context = contextOf(deployment)
        val installer = AgentInstallOperations(client, gate)
        val onHost = runCatching {
            AgentServiceMapping.serviceIDsForServices(
                client.discover().services.map { it.id to it.containers.map { c -> c.name } },
            )
        }.getOrDefault(emptySet())
        val chosen = ServiceInstallPlan.agentRun(
            ServiceRegistry.all.filter { deployment.services.contains(it.id) }, onHost,
        )
        updateParts { it.copy(servicesTotal = chosen.size) }
        if (chosen.isNotEmpty()) {
            val requests = chosen.map { it.id to serviceContext(context, it.id) }
            val started = installer.startPlan(requests, AgentPlanPurpose.SETUP)
            agentPlanStarted = true
            finishPlan(followPlan(installer, started), client, gate)
        }

        if (tunnelConnected) publishTunnelNames()

        revokeInstallKey(jvmRunner)
    }

    /** Once the agent runs the list, scripts stay out */
    @Volatile private var agentPlanStarted = false

    /** How far the setup plan's log is read */
    private val planMark = AgentInstallOperations.PlanLogMark()

    /** Follows the agent's plan through dropped lines */
    private suspend fun followPlan(installer: AgentInstallOperations, started: AgentInstallPlan): AgentInstallPlan {
        var drops = 0
        while (true) {
            try {
                return followPlanOnce(installer, started)
            } catch (error: Exception) {
                if (error is CancellationException || error is AgentError.Rpc ||
                    error is AgentInstallOperations.PlanLost || drops++ >= AGENT_ATTEMPTS * 2
                ) throw error
                _state.value = _state.value.copy(stage = "Reconnecting…")
                delay(3_000)
            }
        }
    }

    private suspend fun followPlanOnce(installer: AgentInstallOperations, started: AgentInstallPlan): AgentInstallPlan =
        installer.followPlan(
            started,
            mark = planMark,
            onService = { id ->
                val name = if (id == "vpn") "VPN" else ServiceRegistry.service(ServiceID(id))?.displayName ?: id
                _state.value = _state.value.copy(stage = "Installing $name…")
            },
            onProgress = { settled, total ->
                updateParts { it.copy(servicesTotal = total, servicesDone = maxOf(it.servicesDone, settled)) }
            },
            onChunk = { chunk -> appendLog(chunk) },
            onWarning = { text -> appendWarning(text) },
        )

    /** Fetches DKIM after mail; throws for missed services */
    private suspend fun finishPlan(plan: AgentInstallPlan, client: AgentClient, gate: AgentChannelGate?) {
        val mail = setOf(ServiceID.MAILCOW, ServiceID.MAILU, ServiceID.DOCKER_MAILSERVER).map { it.rawValue }
        if (plan.items.any { it.state == AgentInstallPlan.State.DONE && it.agentServiceID in mail }) {
            runCatching { AgentDkimOperations(client, gate).fetchRecords() }
        }
        val missed = plan.missed.map { it.agentServiceID }
        if (missed.isNotEmpty()) {
            throw IllegalStateException("Not installed: ${missed.joinToString(", ")}. Start the installation again to retry them.")
        }
    }

    /** One service's agent context; the tunnel gets its connector token */
    private suspend fun serviceContext(given: AgentInstallContext, id: ServiceID): AgentInstallContext {
        val base = AgentInstallSettings.vpnProtocolList(id, deployment.services)?.let { protocols ->
            given.copy(settings = given.settings + (AgentInstallSettings.VPN_PROTOCOLS_KEY to protocols))
        } ?: given
        val setup = tunnel ?: return base
        if (id != ServiceID.CLOUDFLARED) return base
        return try {
            val token = setup.connectorToken(deployment)
            tunnelConnected = true
            base.copy(settings = base.settings + (AgentInstallSettings.CLOUDFLARED_TOKEN_KEY to token))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            appendWarning(failure.message ?: failure::class.simpleName.orEmpty())
            base
        }
    }

    /** Sends the deployment's web names through its tunnel */
    private suspend fun publishTunnelNames() {
        val setup = tunnel ?: return
        try {
            appendLog(setup.publishNames(deployment))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            appendWarning(failure.message ?: failure::class.simpleName.orEmpty())
        }
    }

    private suspend fun revokeInstallKey(runner: SSHCommandRunner) {
        val access = DashboardAccessInput(sshUser = deployment.entry.user, appPublicKey = appPublicKey.orEmpty())
        val command = MailRecipe.revokeInstallKeyCommand(access, AppLanguage.EN)
        val revoked = runCatching { runner.run(command, SSHHostID.VPS, 60.seconds).exitCode == 0 }.getOrDefault(false)
        if (!revoked) appendWarning(OperationNotices.text(R.string.install_key_not_removed))
    }

    private fun updateParts(change: (InstallParts) -> InstallParts) {
        _state.value = _state.value.copy(parts = change(_state.value.parts))
    }

    private fun appendLog(line: String) {
        val text = line.trim()
        if (text.isEmpty()) return
        _state.value = _state.value.copy(log = (_state.value.log + text).takeLast(LOG_LIMIT))
    }

    private fun appendWarning(line: String) {
        val text = line.trim()
        if (text.isEmpty()) return
        _state.value = _state.value.copy(installWarnings = _state.value.installWarnings + text)
    }

    private fun handle(event: SetupEvent, target: InstallTarget) {
        val current = _state.value
        _state.value = when (event) {
            is SetupEvent.Step -> if (current.parts.directServices) {
                current.copy(parts = current.parts.copy(directStep = event.index.toDouble() / maxOf(event.total, 1)))
            } else {
                current.copy(stepIndex = event.index, stepTotal = event.total)
            }
            is SetupEvent.Stage -> current.copy(stage = event.title)
            is SetupEvent.Line -> when (event.text) {
                SetupMarkers.DNS_CHECK_FAILED -> current.copy(sawDNSCheckFailure = true)
                SetupMarkers.PORTS_IN_USE -> current.copy(sawPortConflict = true)
                else -> current.copy(log = (current.log + event.text).takeLast(LOG_LIMIT))
            }
            is SetupEvent.Report -> {
                saveReport(target.kind.name.lowercase(), event.text)
                current.copy(
                    reports = current.reports.filter { it.kind != target.kind } +
                        InstallState.Report(target.kind, event.text)
                )
            }
            is SetupEvent.Reconnecting -> {
                val note = "Connection lost — reconnecting (attempt ${event.attempt}). " +
                    "The installation keeps running on the server."
                current.copy(stage = note, log = (current.log + note).takeLast(LOG_LIMIT))
            }
            SetupEvent.Done -> current
        }
    }

    private companion object {
        const val LOG_LIMIT = 20_000

        /** Tries of the agent step before the direct path */
        const val AGENT_ATTEMPTS = 2
        const val PROBE_ATTEMPTS = 3
        val PROBE_BACKOFF = 2.seconds
        val PROBE_TIMEOUT = 20.seconds
        const val PROBE_TOKEN = "GRYONIXNEXUS_PING"

        val PROBE_COMMAND = "echo $PROBE_TOKEN; . /etc/os-release 2>/dev/null; " +
            "echo \"${SetupMarkers.DISTRIBUTION}:\${ID:-}:\${ID_LIKE:-}\"; " +
            ServerHardware.PROBE_COMMAND + "; " + SudoAccess.PROBE_COMMAND
    }
}
