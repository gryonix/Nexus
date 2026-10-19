package com.skaymer.gryonixnexus.app

import com.skaymer.gryonixnexus.app.notify.OperationDisplay
import com.skaymer.gryonixnexus.app.notify.OperationNotices
import com.skaymer.gryonixnexus.recipe.AgentBootstrapSections
import android.app.Application
import android.content.Context
import gryonixnexusd.v1.HostRole
import com.skaymer.gryonixnexus.servercontrol.DKIMRouting
import com.skaymer.gryonixnexus.servercontrol.SSHDKIMOperations
import com.skaymer.gryonixnexus.agentcontrol.AgentDkimOperations
import com.skaymer.gryonixnexus.agentcontrol.AgentDynamicDNSOperations
import com.skaymer.gryonixnexus.agentcontrol.AgentSecurityOperations
import com.skaymer.gryonixnexus.servercontrol.MailboxRouting
import com.skaymer.gryonixnexus.servercontrol.MailboxOperations
import com.skaymer.gryonixnexus.agentcontrol.AgentMailboxOperations
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.agentclient.AgentHostSurface
import com.skaymer.gryonixnexus.agentcontrol.AgentInstallSettings
import com.skaymer.gryonixnexus.agentcontrol.AgentInstallContext
import com.skaymer.gryonixnexus.servercontrol.RemovalScope
import com.skaymer.gryonixnexus.servercontrol.ServiceRemovalRouting
import com.skaymer.gryonixnexus.servercontrol.SSHServiceRemoval
import com.skaymer.gryonixnexus.agentcontrol.AgentInstallOperations
import com.skaymer.gryonixnexus.app.secrets.DNSCredentialTokenStore
import com.skaymer.gryonixnexus.catalog.ManagedService
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.agentcontrol.AgentServiceRemoval
import com.skaymer.gryonixnexus.agentcontrol.AgentAutoBackupOperations
import com.skaymer.gryonixnexus.agentcontrol.AgentBackupOperations
import com.skaymer.gryonixnexus.agentcontrol.AgentPreRestoreOperations
import com.skaymer.gryonixnexus.agentcontrol.AgentJobOperations
import com.skaymer.gryonixnexus.agentcontrol.AgentCommandRunner
import com.skaymer.gryonixnexus.agentcontrol.AgentContainerOperations
import com.skaymer.gryonixnexus.agentcontrol.AgentMeshOperations
import com.skaymer.gryonixnexus.agentcontrol.AgentMetricsHistory
import com.skaymer.gryonixnexus.agentcontrol.AgentServiceLogs
import com.skaymer.gryonixnexus.agentcontrol.AgentRestoreOperations
import com.skaymer.gryonixnexus.agentcontrol.AgentUpdateOperations
import com.skaymer.gryonixnexus.agentcontrol.AgentVPNClientOperations
import com.skaymer.gryonixnexus.app.vpn.VPNMoveText
import com.skaymer.gryonixnexus.app.vpn.VPNMoveViewModel
import com.skaymer.gryonixnexus.app.vpn.VPNRelayRouting
import com.skaymer.gryonixnexus.servercontrol.agentHost
import com.skaymer.gryonixnexus.servercontrol.vpnHost
import com.skaymer.gryonixnexus.servercontrol.vpnRunsOnRelay
import com.skaymer.gryonixnexus.app.dns.DKIMViewModel
import com.skaymer.gryonixnexus.app.dns.DynamicDNSViewModel
import com.skaymer.gryonixnexus.app.hosts.HostProbesViewModel
import com.skaymer.gryonixnexus.app.security.SecurityViewModel
import com.skaymer.gryonixnexus.servercontrol.StatusOperations
import com.skaymer.gryonixnexus.app.mail.MailboxesViewModel
import com.skaymer.gryonixnexus.app.servers.AddMachineViewModel
import com.skaymer.gryonixnexus.app.servers.AddServiceViewModel
import com.skaymer.gryonixnexus.app.servers.ServiceRemovalViewModel
import com.skaymer.gryonixnexus.app.access.AccessCredentialStore
import com.skaymer.gryonixnexus.app.access.AccessViewModel
import com.skaymer.gryonixnexus.app.devices.DevicesViewModel
import com.skaymer.gryonixnexus.app.access.InstallReportImport
import com.skaymer.gryonixnexus.app.access.InstallReportStore
import com.skaymer.gryonixnexus.agentcontrol.AgentDeviceOperations
import com.skaymer.gryonixnexus.agentcontrol.AgentVaultOperations
import com.skaymer.gryonixnexus.agentcontrol.AgentModOperations
import com.skaymer.gryonixnexus.app.ai.LocalModelsViewModel
import com.skaymer.gryonixnexus.app.servers.ModsViewModel
import com.skaymer.gryonixnexus.app.ai.ModelKeysViewModel
import com.skaymer.gryonixnexus.app.agent.AgentBootstrapOperations
import com.skaymer.gryonixnexus.app.agent.AgentSessions
import com.skaymer.gryonixnexus.app.access.SudoPrompter
import com.skaymer.gryonixnexus.app.access.SudoReadiness
import com.skaymer.gryonixnexus.app.agent.AgentInstallViewModel
import com.skaymer.gryonixnexus.app.agent.AgentSelfUpdateViewModel
import com.skaymer.gryonixnexus.transport.SSHJFileBrowser
import com.skaymer.gryonixnexus.app.agent.RunStopper
import com.skaymer.gryonixnexus.app.agent.RunningJobs
import com.skaymer.gryonixnexus.app.updates.AppUpdateViewModel
import com.skaymer.gryonixnexus.app.configurator.ConfiguratorHistory
import com.skaymer.gryonixnexus.app.configurator.ConfiguratorViewModel
import com.skaymer.gryonixnexus.app.containers.AgentContainers
import com.skaymer.gryonixnexus.app.containers.ContainersViewModel
import com.skaymer.gryonixnexus.app.files.FileBrowserViewModel
import com.skaymer.gryonixnexus.app.logs.ServiceLogsViewModel
import com.skaymer.gryonixnexus.app.install.InstallRegistry
import com.skaymer.gryonixnexus.app.install.InstallSessions
import com.skaymer.gryonixnexus.app.mesh.AgentMesh
import com.skaymer.gryonixnexus.app.mesh.MeshViewModel
import com.skaymer.gryonixnexus.app.metrics.EnergySettings
import com.skaymer.gryonixnexus.app.storage.StorageViewModel
import com.skaymer.gryonixnexus.app.speed.SpeedTestHistory
import com.skaymer.gryonixnexus.app.speed.SpeedTestViewModel
import com.skaymer.gryonixnexus.app.metrics.HistoryViewModel
import com.skaymer.gryonixnexus.app.metrics.MetricPanelStore
import com.skaymer.gryonixnexus.app.metrics.MetricsBoardViewModel
import com.skaymer.gryonixnexus.app.security.SecuritySettings
import com.skaymer.gryonixnexus.app.secrets.DeploymentSecrets
import com.skaymer.gryonixnexus.app.secrets.DeviceIdentity
import com.skaymer.gryonixnexus.app.secrets.KeystoreSecretStore
import com.skaymer.gryonixnexus.app.secrets.AppIdentities
import com.skaymer.gryonixnexus.app.configurator.DNSProviderKind
import com.skaymer.gryonixnexus.app.secrets.DNSCredentials
import com.skaymer.gryonixnexus.app.servers.WakeOnLANViewModel
import com.skaymer.gryonixnexus.app.secrets.CloudflareTokenStore
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.terminal.TerminalDirectHostStore
import com.skaymer.gryonixnexus.app.terminal.ShellUserViewModel
import com.skaymer.gryonixnexus.app.terminal.TerminalSessions
import com.skaymer.gryonixnexus.app.servers.BackupsViewModel
import com.skaymer.gryonixnexus.app.servers.DeploymentEraser
import com.skaymer.gryonixnexus.app.servers.EraseViewModel
import com.skaymer.gryonixnexus.app.servers.FleetMetrics
import com.skaymer.gryonixnexus.app.servers.DeploymentTransferService
import com.skaymer.gryonixnexus.app.servers.AdoptViewModel
import com.skaymer.gryonixnexus.app.servers.FleetRepository
import com.skaymer.gryonixnexus.app.servers.ServerAccessStore
import com.skaymer.gryonixnexus.app.servers.HostActionsViewModel
import com.skaymer.gryonixnexus.app.servers.RelayStatusViewModel
import com.skaymer.gryonixnexus.agentcontrol.AgentAdminLockdown
import com.skaymer.gryonixnexus.servercontrol.LockdownRouting
import com.skaymer.gryonixnexus.servercontrol.SSHAdminLockdown
import com.skaymer.gryonixnexus.app.servers.HostCleanup
import com.skaymer.gryonixnexus.app.servers.AgentBackupSchedule
import com.skaymer.gryonixnexus.app.servers.SSHBackupSchedule
import com.skaymer.gryonixnexus.app.servers.ServiceControlViewModel
import com.skaymer.gryonixnexus.app.servers.UpdatesViewModel
import com.skaymer.gryonixnexus.app.session.ConnectionCheck
import com.skaymer.gryonixnexus.app.session.ServerSessions
import com.skaymer.gryonixnexus.app.session.SshjSecurity
import com.skaymer.gryonixnexus.app.shell.AppNavigator
import com.skaymer.gryonixnexus.app.shell.PreferencesStore
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import com.skaymer.gryonixnexus.app.servers.ConnectionSettings
import com.skaymer.gryonixnexus.app.servers.SilenceWatch
import com.skaymer.gryonixnexus.app.shell.ServerSectionSettings
import com.skaymer.gryonixnexus.app.shell.TabBarSettings
import com.skaymer.gryonixnexus.app.shell.WelcomeState
import com.skaymer.gryonixnexus.app.vpn.AgentVPNClients
import com.skaymer.gryonixnexus.app.vpn.EndpointPinStore
import com.skaymer.gryonixnexus.app.vpn.LastTunnel
import com.skaymer.gryonixnexus.app.vpn.OnDemandMonitor
import com.skaymer.gryonixnexus.app.vpn.OnDemandSettings
import com.skaymer.gryonixnexus.app.vpn.OwnVpnDevices
import com.skaymer.gryonixnexus.app.vpn.VPNClientNotices
import com.skaymer.gryonixnexus.app.vpn.VPNClientsViewModel
import com.skaymer.gryonixnexus.app.vpn.VpnSessionNotice
import com.skaymer.gryonixnexus.app.vpn.VpnSessionNoticeSettings
import com.skaymer.gryonixnexus.app.vpn.VpnTunnel
import com.skaymer.gryonixnexus.servercontrol.AgentServiceMapping
import com.skaymer.gryonixnexus.servercontrol.AutoBackupOperations
import com.skaymer.gryonixnexus.servercontrol.AutoBackupRouting
import com.skaymer.gryonixnexus.servercontrol.BackupRouting
import com.skaymer.gryonixnexus.servercontrol.Deployment
import com.skaymer.gryonixnexus.servercontrol.FileDeploymentStore
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryProbe
import com.skaymer.gryonixnexus.servercontrol.MetricsHistoryRouting
import com.skaymer.gryonixnexus.servercontrol.RestoreRouting
import com.skaymer.gryonixnexus.servercontrol.SSHServiceBackups
import com.skaymer.gryonixnexus.servercontrol.SSHServiceControl
import com.skaymer.gryonixnexus.servercontrol.SSHServiceRestore
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRoute
import com.skaymer.gryonixnexus.servercontrol.ServiceControlRouting
import com.skaymer.gryonixnexus.servercontrol.ServiceOperations
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateOperations
import com.skaymer.gryonixnexus.servercontrol.ServiceUpdateRouting
import com.skaymer.gryonixnexus.servercontrol.UninstallOperations
import java.io.File
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/** Process-wide root */
class GryonixApplication : Application() {
    lateinit var store: SettingsStore
        private set
    lateinit var tabs: TabBarSettings
        private set

    lateinit var security: SecuritySettings
        private set

    /** Whether a newer APK has been published — see `AppUpdate` */
    lateinit var appUpdates: AppUpdateViewModel
        private set

    /** Taking over a machine that already runs the agent */
    lateinit var adopt: AdoptViewModel
        private set

    /** Restart sshd, reboot, and the guard over the admin panels */
    lateinit var hostActions: HostActionsViewModel
    lateinit var systemUpdates: com.skaymer.gryonixnexus.app.servers.SystemUpdateViewModel

    lateinit var wakeOnLAN: WakeOnLANViewModel

    /** The relay path's three rows — see `RelayStatusCard` */
    lateinit var relayStatus: RelayStatusViewModel
        private set

    /** Moving one server, with its secrets, to another device */
    lateinit var transfer: DeploymentTransferService
        private set

    /** Per-server section arrangement — the strip on a server's own screen */
    lateinit var sections: ServerSectionSettings
        private set
    lateinit var fleet: FleetRepository
        private set

    /** Does what the buttons on server alerts ask */
    lateinit var alertActions: com.skaymer.gryonixnexus.app.notify.AlertActionRunner
        private set
    val navigator = AppNavigator()

    lateinit var configurator: ConfiguratorViewModel
        private set

    lateinit var secrets: SecretStore

    /** Which installation of this app is calling — see [DeviceIdentity] */
    lateinit var deviceIdentity: DeviceIdentity
        private set

    /** What this copy may do — see `LicenseStore` */
    lateinit var license: com.skaymer.gryonixnexus.app.licensing.LicenseStore
        private set

    /** Whether the welcome has been said — see `WelcomeState` */
    lateinit var welcome: WelcomeState
        private set

    /** The Cloudflare API tokens — see `CloudflareTokenStore` */
    lateinit var cloudflare: CloudflareTokenStore

    /** The named Cloudflare accounts this device holds tokens for */
    lateinit var dnsCredentials: DNSCredentials

    /** The tunnel this device brings up itself — see `VpnTunnel` */
    lateinit var vpnTunnel: VpnTunnel
        private set

    lateinit var terminalHosts: TerminalDirectHostStore
        private set

    /** Where a terminal gets its own connection — see `TerminalSessions` */
    lateinit var terminals: TerminalSessions
        private set

    lateinit var connectionCheck: ConnectionCheck
        private set

    /** The live readings behind the cards */
    lateinit var metrics: FleetMetrics
        private set

    lateinit var history: HistoryViewModel
    lateinit var energy: EnergySettings
    lateinit var storage: StorageViewModel
    lateinit var storageOverview: com.skaymer.gryonixnexus.app.storage.StorageOverview
    lateinit var speed: SpeedTestViewModel
    lateinit var processes: com.skaymer.gryonixnexus.app.servers.TopProcessesViewModel
        private set

    lateinit var metricsBoard: MetricsBoardViewModel
        private set

    /** The board itself — which machine, which metrics, which period */
    lateinit var metricPanels: MetricPanelStore
        private set

    /** What the servers are doing while nobody is looking */
    lateinit var runningJobs: RunningJobs
        private set

    /** Managing the services of whichever server is open */
    lateinit var services: ServiceControlViewModel
        private set

    lateinit var updates: UpdatesViewModel
        private set

    lateinit var backups: BackupsViewModel
        private set

    lateinit var mesh: MeshViewModel
        private set

    /** The sign-in details of whichever server is open */
    lateinit var access: AccessViewModel

    lateinit var modelKeys: ModelKeysViewModel
    lateinit var localModels: LocalModelsViewModel
        private set

    lateinit var mods: ModsViewModel
        private set

    /** The devices paired to one server's agent — see [DevicesViewModel] */
    lateinit var devices: DevicesViewModel
        private set

    lateinit var vpnClients: VPNClientsViewModel
        private set

    /** Moves a server's VPN between home and its relay */
    lateinit var vpnMove: VPNMoveViewModel
        private set

    /** What every machine in the fleet is running */
    lateinit var containers: ContainersViewModel
        private set

    lateinit var addMachine: AddMachineViewModel
        private set

    lateinit var dkim: DKIMViewModel
        private set

    lateinit var dynamicDNS: DynamicDNSViewModel
    lateinit var vaultwardenTwoFactor: com.skaymer.gryonixnexus.app.servers.VaultwardenTwoFactorViewModel
        private set
    lateinit var homeDoors: com.skaymer.gryonixnexus.app.servers.HomeDoors
    lateinit var agentRemoval: com.skaymer.gryonixnexus.app.agent.AgentRemoval
    lateinit var notify: com.skaymer.gryonixnexus.app.notify.NotifyViewModel
        private set

    lateinit var hostSecurity: SecurityViewModel

    lateinit var shellUsers: ShellUserViewModel

    /** Each machine's own tunnel, memory and volumes — see `HostCard` */
    lateinit var hostProbes: HostProbesViewModel
        private set

    lateinit var mailboxes: MailboxesViewModel
        private set

    lateinit var addService: AddServiceViewModel
        private set

    /** Taking ONE service off a server */
    lateinit var serviceRemoval: ServiceRemovalViewModel
    lateinit var serviceMove: com.skaymer.gryonixnexus.app.servers.ServiceMoveViewModel
        private set

    lateinit var serviceLogs: ServiceLogsViewModel
        private set

    /** The disk of whichever server is open */
    lateinit var files: FileBrowserViewModel
        private set

    lateinit var erase: EraseViewModel
        private set

    /** The install in flight, if any */
    lateinit var agentInstall: AgentInstallViewModel
    lateinit var agentUpdateOffer: com.skaymer.gryonixnexus.app.agent.AgentUpdateOffer

        private set

    /** Asks a non-root sign-in's sudo password once */
    val sudoPrompter = SudoPrompter()

    /** DNS records waiting for the user's yes */
    val dnsUpdate = kotlinx.coroutines.flow.MutableStateFlow<com.skaymer.gryonixnexus.app.servers.ServiceDNSPublisher.Update?>(null)
    /** What the last DNS update said */
    val dnsUpdateResult = kotlinx.coroutines.flow.MutableStateFlow<List<String>?>(null)

    fun applyDNSUpdate(update: com.skaymer.gryonixnexus.app.servers.ServiceDNSPublisher.Update) {
        dnsUpdate.value = null
        background.launch {
            dnsUpdateResult.value = servicePublisher().apply(update)
            if (update.add.isNotEmpty()) runCatching { agents.client(update.after).refreshCertificates() }
        }
    }

    lateinit var agentSelfUpdate: AgentSelfUpdateViewModel
        private set

    lateinit var installs: InstallRegistry
        private set

    /** The scope the poll loops live in */
    private val background = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** The live SSH session of every server, one per machine */
    private lateinit var sessions: ServerSessions

    private lateinit var agents: AgentSessions

    /** Take a server off the list for good */
    fun forget(deploymentID: String) {
        fleet.remove(deploymentID)
        sections.forget(deploymentID)
        background.launch { sessions.disconnect(deploymentID) }
    }

    private fun hostSurfaceContext(
        deployment: Deployment,
        role: HostRole = if (deployment.hasRelayIngress) {
            HostRole.HOST_ROLE_HOME_BACKEND
        } else {
            HostRole.HOST_ROLE_SINGLE_HOST
        },
    ): AgentInstallContext =
        AgentInstallContext(
            domain = deployment.domain,
            additionalDomains = deployment.additionalDomains,
            localOnly = deployment.scope.usesInternalTLS,
            adminUsername = deployment.serviceSettings.adminUsername,
            settings = AgentInstallSettings.map(deployment.serviceSettings),
            host = hostSurface(deployment, role),
        )

    private fun moveInstallContext(
        deployment: Deployment,
        route: com.skaymer.gryonixnexus.servercontrol.ServiceMoveRoute,
    ): AgentInstallContext {
        val base = hostSurfaceContext(deployment)
        if (route.targetIsFront) return base
        val key = AppIdentities(secrets).publicKey(deployment.id).orEmpty()
        return base.copy(
            localOnly = true,
            host = AgentHostSurface(role = HostRole.HOST_ROLE_SINGLE_HOST, dashboardPublicKey = key),
        )
    }

    /** The host surface, with a pair's tunnel and forwards */
    private fun hostSurface(deployment: Deployment, role: HostRole): AgentHostSurface =
        com.skaymer.gryonixnexus.app.servers.RelayHostSurface.of(
            deployment, role, AppIdentities(secrets).publicKey(deployment.id).orEmpty(),
        )

    /** The host surface for one service, with its machine's role */
    private fun serviceSurfaceContext(deployment: Deployment, service: ServiceID?): AgentInstallContext =
        VPNRelayRouting.surfaceRole(deployment, service)?.let { hostSurfaceContext(deployment, it) }
            ?: hostSurfaceContext(deployment)

    /** Installs these VPN protocols at once on the VPN's machine */
    private suspend fun installVPNProtocols(deployment: Deployment, protocols: Set<ServiceID>, onChunk: (String) -> Unit) {
        val anchor = ServiceRegistry.all.first { it.id in protocols }.id
        val context = serviceSurfaceContext(deployment, anchor).let { base ->
            val list = AgentInstallSettings.vpnProtocolList(anchor, protocols).orEmpty()
            base.copy(settings = base.settings + (AgentInstallSettings.VPN_PROTOCOLS_KEY to list))
        }
        AgentInstallOperations(client = agents.client(deployment, deployment.vpnHost), gate = agents.gate(deployment))
            .install(anchor, context, onChunk = onChunk)
    }

    /** Sends the relay its forwards and role again */
    private suspend fun reprovisionRelay(deployment: Deployment): List<String> {
        val relay = agents.client(deployment, com.skaymer.gryonixnexus.servercontrol.SSHHostID.VPS)
        return AgentInstallOperations(client = relay, gate = agents.gate(deployment))
            .provisionHost(hostSurfaceContext(deployment, HostRole.HOST_ROLE_VPS_RELAY)).notes
    }

    /** DNS names and relay forwards for a newly added service */
    private suspend fun afterAddingService(deployment: Deployment, service: ManagedService, portsChanged: Boolean): List<String> {
        val (update, dnsNotes) = servicePublisher().pendingAdd(service, deployment)
        if (update != null) dnsUpdate.value = update
        val notes = dnsNotes.toMutableList()
        if (service.id == ServiceID.CLOUDFLARED) notes += tunnelNames(deployment)
        if (portsChanged && deployment.hasRelayIngress) {
            try {
                notes += reprovisionRelay(deployment)
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                notes += getString(R.string.add_service_relay_failed, error.message ?: error::class.simpleName)
            }
        }
        return notes
    }

    /** The deployment's web names, sent through its tunnel */
    private suspend fun tunnelNames(deployment: Deployment): String = try {
        tunnelSetup().publishNames(deployment)
    } catch (cancelled: kotlinx.coroutines.CancellationException) {
        throw cancelled
    } catch (error: Exception) {
        error.message ?: error::class.simpleName.orEmpty()
    }

    /** Cloudflare Tunnel through the saved tunnel and DNS tokens */
    private fun tunnelSetup(): com.skaymer.gryonixnexus.app.servers.TunnelSetup {
        val tokens = DNSCredentialTokenStore(secrets)
        return com.skaymer.gryonixnexus.app.servers.TunnelSetup(
            tunnelToken = { tokens.currentCloudflareTunnelToken(dnsCredentials) },
            dnsToken = {
                val chosen = dnsCredentials.selected?.takeIf { it.kind == DNSProviderKind.CLOUDFLARE }
                    ?: dnsCredentials.all.firstOrNull { it.kind == DNSProviderKind.CLOUDFLARE }
                chosen?.let { tokens.token(it) }
            },
            tokenMissing = getString(R.string.tunnel_token_missing),
            published = { getString(R.string.tunnel_names_published, it) },
        )
    }

    /** Publishes and removes service names through the saved DNS token */
    private fun servicePublisher() = com.skaymer.gryonixnexus.app.servers.ServiceDNSPublisher(
            provider = {
                val credential = dnsCredentials.selected ?: dnsCredentials.all.firstOrNull()
                credential?.let { DNSCredentialTokenStore(secrets).token(it) }
                    ?.takeIf { it.isNotBlank() }
                    ?.let { credential.kind.makeProvider(it) }
            },
            text = com.skaymer.gryonixnexus.app.servers.ServiceDNSPublisher.Text(
                point = { getString(R.string.add_service_dns_point, it) },
                manual = { getString(R.string.add_service_dns_manual, it) },
                done = { getString(R.string.add_service_dns_done, it) },
                failed = { zone, count -> getString(R.string.add_service_dns_failed, zone, count) },
                removed = { zone, count -> getString(R.string.remove_service_dns_removed, zone, count) },
                byHand = { getString(R.string.remove_service_dns_by_hand, it) },
                elsewhere = { name, address -> getString(R.string.add_service_dns_elsewhere, name, address) },
            ),
        )

    override fun onCreate() {
        super.onCreate()
        OperationNotices.install(this)
        createStores()
        createSessions()
        createAgentLifecycle()
        createDashboard()
        createMaintenance()
        createBackups()
        createHostTools()
        createMailTools()
        createServiceTools()
        createAgentViews()
        createVaultViews()
        fleet.reload()
        syncNotifyEverywhere()
    }

    /** Every agent server learns this phone, whatever screen is open */
    fun syncNotifyEverywhere() {
        if (fleet.isDemo) return
        fleet.deployments.value.forEach(notify::sync)
    }

    private fun createStores() {
        store = PreferencesStore(getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE))
        OperationNotices.display = { OperationDisplay.load(store) }
        val installed = AppUpdateViewModel.installedVersion(this)
        appUpdates = AppUpdateViewModel(store, installed.first, installed.second)
        welcome = WelcomeState(store)
        tabs = TabBarSettings(store)
        security = SecuritySettings(store)
        sections = ServerSectionSettings(store)
        secrets = KeystoreSecretStore(
            getSharedPreferences(SECRETS, Context.MODE_PRIVATE)
        )
        val deploymentFile = FileDeploymentStore(File(filesDir, "deployments.json"))
        transfer = DeploymentTransferService(secrets, deploymentFile)
        fleet = FleetRepository(
            store = deploymentFile,
            settings = store,
            eraser = DeploymentEraser(secrets, store),
        )
        terminals = TerminalSessions(secrets)
        vpnTunnel = VpnTunnel(applicationContext)
        val sessionNotice = VpnSessionNoticeSettings(store)
        vpnTunnel.noticeSettings = sessionNotice
        val onDemand = OnDemandSettings(store)
        vpnTunnel.lastTunnel = LastTunnel(secrets)
        vpnTunnel.endpointPins = EndpointPinStore(getSharedPreferences(EndpointPinStore.FILE, Context.MODE_PRIVATE))
        vpnTunnel.onDemand = onDemand
        OnDemandMonitor(applicationContext, vpnTunnel, onDemand, LastTunnel(secrets), refresh = ::refreshedTunnel).start()
        VpnSessionNotice(applicationContext, vpnTunnel, sessionNotice).follow(background)
        dnsCredentials = DNSCredentials(store, secrets)
        cloudflare = CloudflareTokenStore(secrets) {
            dnsCredentials.selected?.takeIf { it.kind == DNSProviderKind.CLOUDFLARE }?.id
                ?: dnsCredentials.all.firstOrNull { it.kind == DNSProviderKind.CLOUDFLARE }?.id
                ?: DNSCredentials.CLOUDFLARE_FIRST_ID
        }
        terminalHosts = TerminalDirectHostStore(File(filesDir, "terminal-hosts.json"))
        configurator = ConfiguratorViewModel(
            fleet = fleet,
            secrets = secrets,
            history = ConfiguratorHistory(File(filesDir, "configurator-history.json")),
            scope = background,
            agentClient = { deployment ->
                if (!deployment.usesAgent) null else agents.client(deployment)
            },
            releaseAgent = { sessions.release(it.id) },
            onGenerated = { license.noteFirstGeneration() },
        )
    }

    private fun createSessions() {
        SshjSecurity.install()
        sessions = ServerSessions(secrets, store, fleet = { fleet.deployments.value })
        connectionCheck = ConnectionCheck(sessions)
        metrics = FleetMetrics(
            scope = background,
            runners = { sessions.runner(it) },
            release = { sessions.release(it.id) },
            silence = SilenceWatch(
                waits = { ConnectionSettings.waits(store) },
                reason = { seconds -> getString(com.skaymer.gryonixnexus.R.string.metrics_silent_host, seconds) },
            ),
        )
        energy = EnergySettings(getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE))
        storage = StorageViewModel(
            scope = background,
            control = { sessions.runner(it) },
            root = { id, target -> InstallSessions(secrets).runner(id, target) },
            agent = { deployment, host -> agents.client(deployment, host) },
        )
        storageOverview = com.skaymer.gryonixnexus.app.storage.StorageOverview(
            scope = background,
            control = { sessions.runner(it) },
        )
        processes = com.skaymer.gryonixnexus.app.servers.TopProcessesViewModel(
            scope = background,
            runners = { sessions.runner(it) },
        )
        speed = SpeedTestViewModel(
            scope = background,
            history = SpeedTestHistory(getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)),
            control = { sessions.runner(it) },
        )
        history = HistoryViewModel(
            scope = background,
            runners = { sessions.runner(it) },
            release = { sessions.release(it.id) },
            profiles = { serverId, host -> energy.profile(serverId, host) },
            detectPower = { serverId, host, runner -> energy.detect(serverId, host, runner) },
            estimates = { serverId, host -> energy.estimate(serverId, host) },
        )
        metricPanels = MetricPanelStore(store)
        deviceIdentity = DeviceIdentity(secrets)
        license = com.skaymer.gryonixnexus.app.licensing.LicenseStore(
            secrets, deviceUid = { deviceIdentity.uid }, deviceName = android.os.Build.MODEL,
        )
        val claim = com.skaymer.gryonixnexus.app.servers.TransferClaim(
            secrets, deviceUID = { deviceIdentity.uid }, deviceLabel = { android.os.Build.MODEL },
        )
        agents = AgentSessions(
            runners = { sessions.runner(it) },
            deviceUID = { deviceIdentity.uid },
            onOpened = claim::claimIfPending,
        )
        transfer.mintKey = { deployment ->
            if (deployment.usesAgent) {
                com.skaymer.gryonixnexus.app.servers.mintTransferKey(agents.client(deployment))
            } else {
                null
            }
        }
    }

    private fun createAgentLifecycle() {
        agentInstall = AgentInstallViewModel(
            scope = background,
            runners = { sessions.runner(it) },
            browsers = { SSHJFileBrowser(sessions.runner(it)) },
            sources = { assets.open("agent-src.bin").use { it.readBytes() } },
            version = { agents.client(it).getState().agent_version },
            ensureSudo = { ensureSudo(it, allowing = AgentBootstrapSections.SCRIPT_PATH) },
            onAgentFound = { fleet.update(it) },
            release = { sessions.release(it.id) },
        )
        agentRemoval = com.skaymer.gryonixnexus.app.agent.AgentRemoval(
            scope = background,
            remove = { agents.client(it).removeAgent() },
            save = { fleet.update(it) },
        )
        agentUpdateOffer = com.skaymer.gryonixnexus.app.agent.AgentUpdateOffer(
            scope = background,
            fleet = { fleet.deployments.value.filter { !fleet.isDemo } },
            installed = { deployment, host -> agents.client(deployment, host).getState().agent_version },
            install = { deployment ->
                agentInstall.reset()
                agentInstall.install(deployment)
                agentInstall.state.first { it.isFinished }
            },
            published = { deployment, host ->
                agents.client(deployment, host).getAgentUpdateStatus()
                    .takeIf { it.update_available }?.available_version
            },
            applyPublished = { deployment ->
                agentSelfUpdate.apply(deployment)
                agentSelfUpdate.state.first { !it.isApplying }
            },
        )
        agentSelfUpdate = AgentSelfUpdateViewModel(
            scope = background,
            client = { agents.client(it) },
            hostClient = { deployment, host -> agents.client(deployment, host) },
        )
        runningJobs = RunningJobs(
            scope = background,
            deployments = { fleet.deployments.value },
            operations = { AgentJobOperations(agents.client(it)) },
            runners = { sessions.runner(it) },
            followedHere = { it in followedPlans },
        )
        val runStopper = RunStopper { AgentJobOperations(agents.client(it)) }
        OperationNotices.agentStopper = runStopper::stop
    }

    private fun createDashboard() {
        metricsBoard = MetricsBoardViewModel(
            scope = background,
            runners = { sessions.runner(it) },
            release = { sessions.release(it.id) },
            readers = { deployment, host, runner ->
                val ssh = MetricsHistoryProbe(runner, deployment.timeouts.quickSeconds.seconds)
                when (MetricsHistoryRouting.route(
                    usesAgent = deployment.usesAgent,
                    agentTransportAvailable = true,
                    host = host,
                    agentHost = deployment.servicesHost,
                )) {
                    ServiceControlRoute.AGENT -> AgentMetricsHistory(
                        client = agents.client(deployment),
                        gate = agents.gate(deployment),
                    )
                    ServiceControlRoute.SSH -> ssh
                }
            },
        )
        services = ServiceControlViewModel(
            scope = background,
            runners = { sessions.runner(it) },
            release = { sessions.release(it.id) },
            control = { deployment, runner ->
                when (ServiceControlRouting.route(
                    usesAgent = deployment.usesAgent,
                    agentTransportAvailable = true,
                )) {
                    ServiceControlRoute.AGENT -> AgentCommandRunner(
                        client = agents.client(deployment),
                        gate = agents.gate(deployment),
                    )
                    ServiceControlRoute.SSH -> SSHServiceControl(runner, deployment)
                }
            },
            agentTransportAvailable = true,
        )
        adopt = AdoptViewModel(
            scope = background,
            runners = { sessions.runner(it) },
            clients = { agents.client(it) },
            devicePublicKey = { AppIdentities(secrets).publicKey(it.id) },
            deviceLabel = android.os.Build.MODEL ?: "Android",
            deviceUID = { deviceIdentity.uid },
            release = { sessions.release(it.id) },
        )
        relayStatus = RelayStatusViewModel(
            scope = background,
            runners = { sessions.runner(it) },
            release = { sessions.release(it.id) },
        )
        wakeOnLAN = WakeOnLANViewModel(
            scope = background,
            runners = { sessions.runner(it) },
            save = { fleet.update(it) },
            release = { sessions.release(it.id) },
            agentReading = { agents.client(it).getState().wake_on_lan },
        )
    }

    private fun createMaintenance() {
        systemUpdates = com.skaymer.gryonixnexus.app.servers.SystemUpdateViewModel(
            scope = background,
            runners = { sessions.runner(it) },
            release = { sessions.release(it.id) },
        )
        hostActions = HostActionsViewModel(
            scope = background,
            runners = { sessions.runner(it) },
            lockdowns = { deployment ->
                when (LockdownRouting.route(
                    usesAgent = deployment.usesAgent,
                    agentTransportAvailable = true,
                )) {
                    ServiceControlRoute.AGENT -> AgentAdminLockdown(
                        client = agents.client(deployment),
                        gate = agents.gate(deployment),
                    )
                    ServiceControlRoute.SSH -> SSHAdminLockdown(
                        sessions.runner(deployment),
                        deployment.dashboardConfig,
                        deployment.servicesHost,
                    )
                }
            },
            release = { sessions.release(it.id) },
        )
        erase = EraseViewModel(
            scope = background,
            cleanups = { deployment ->
                val ops = UninstallOperations(sessions.runner(deployment), deployment)
                HostCleanup { purge, onEvent -> ops.fullCleanup(purge, onEvent) }
            },
            release = { sessions.release(it.id) },
        )
        updates = UpdatesViewModel(
            scope = background,
            updates = { deployment ->
                when (ServiceUpdateRouting.route(
                    usesAgent = deployment.usesAgent,
                    agentTransportAvailable = true,
                )) {
                    ServiceControlRoute.AGENT -> AgentUpdateOperations(
                        client = agents.client(deployment),
                        gate = agents.gate(deployment),
                    )
                    ServiceControlRoute.SSH -> ServiceUpdateOperations(
                        runner = sessions.runner(deployment),
                        deployment = deployment,
                    )
                }
            },
            release = { sessions.release(it.id) },
            agentTransportAvailable = true,
            onLostConnection = { runningJobs.sweep() },
        )
    }

    private fun createBackups() {
        backups = BackupsViewModel(
            scope = background,
            backups = { deployment, service ->
                val runner = sessions.runner(deployment)
                val ssh = SSHServiceBackups(runner, deployment)
                val kind = ServiceOperations(runner, deployment, service).backupKind
                val route = BackupRouting.route(
                    usesAgent = deployment.usesAgent,
                    agentTransportAvailable = true,
                    kind = kind,
                )
                if (route == ServiceControlRoute.AGENT &&
                    AgentServiceMapping.agentID(service.id) != null
                ) {
                    AgentBackupOperations(
                        client = agents.client(deployment),
                        gate = agents.gate(deployment),
                    )
                } else {
                    ssh
                }
            },
            restores = { deployment, service ->
                val runner = sessions.runner(deployment)
                val route = RestoreRouting.route(
                    usesAgent = deployment.usesAgent,
                    agentTransportAvailable = true,
                )
                if (route == ServiceControlRoute.AGENT &&
                    AgentServiceMapping.agentID(service.id) != null
                ) {
                    AgentRestoreOperations(
                        client = agents.client(deployment),
                        gate = agents.gate(deployment),
                    )
                } else {
                    SSHServiceRestore(runner, deployment)
                }
            },
            schedules = { deployment ->
                when (AutoBackupRouting.route(
                    usesAgent = deployment.usesAgent,
                    agentTransportAvailable = true,
                )) {
                    ServiceControlRoute.AGENT -> AgentBackupSchedule(
                        AgentAutoBackupOperations(
                            client = agents.client(deployment),
                            gate = agents.gate(deployment),
                        )
                    )
                    ServiceControlRoute.SSH -> SSHBackupSchedule(
                        AutoBackupOperations(sessions.runner(deployment), deployment)
                    )
                }
            },
            release = { sessions.release(it.id) },
            browsers = { SSHJFileBrowser(sessions.runner(it)) },
            runners = { sessions.runner(it) },
            oldCopies = { deployment, service ->
                if (deployment.usesAgent && AgentServiceMapping.agentID(service.id) != null) {
                    AgentPreRestoreOperations(
                        client = agents.client(deployment),
                        gate = agents.gate(deployment),
                    )
                } else {
                    null
                }
            },
        )
    }

    private fun createHostTools() {
        addMachine = AddMachineViewModel(
            scope = background,
            trialRunners = { sessions.detached(it) },
            rememberPassword = { deployment, node, password ->
                DeploymentSecrets(secrets, deployment.id).setPassword(password, node.sshHost)
            },
            persist = { fleet.update(it) },
        )
        dkim = DKIMViewModel(
            scope = background,
            records = { deployment ->
                val hasEngine = DKIMViewModel.hasMailEngine(deployment)
                when (DKIMRouting.route(
                    usesAgent = deployment.usesAgent,
                    agentTransportAvailable = true,
                    hasMailEngine = hasEngine,
                )) {
                    ServiceControlRoute.AGENT -> AgentDkimOperations(
                        client = agents.client(deployment),
                        gate = agents.gate(deployment),
                    )
                    ServiceControlRoute.SSH -> SSHDKIMOperations(
                        sessions.runner(deployment),
                        deployment,
                    )
                }
            },
            release = { sessions.release(it.id) },
        )
        homeDoors = com.skaymer.gryonixnexus.app.servers.HomeDoors(
            scope = background,
            client = { agents.client(it) },
        )
        createAgentTools()
        shellUsers = ShellUserViewModel(
            scope = background,
            publicKey = { AppIdentities(secrets).publicKey(it.id) },
            runner = { sessions.runner(it) },
        )
        hostProbes = HostProbesViewModel(
            scope = background,
            disk = { deployment, host ->
                StatusOperations(sessions.runner(deployment), deployment.dashboardConfig)
                    .disk(host)
            },
            memory = { deployment, host ->
                StatusOperations(sessions.runner(deployment), deployment.dashboardConfig)
                    .memory(host)
            },
            wireGuard = { deployment, host ->
                StatusOperations(sessions.runner(deployment), deployment.dashboardConfig)
                    .wgStatus(host)
            },
        )
    }

    /** The saved tunnel as its server knows it now */
    private suspend fun refreshedTunnel(profile: com.skaymer.gryonixnexus.app.vpn.LastTunnel.Profile):
        com.skaymer.gryonixnexus.app.vpn.LastTunnel.Profile? {
        val deployment = fleet.deployments.value.filter { it.name == profile.server }.singleOrNull() ?: return null
        val label = android.os.Build.MODEL ?: "Android"
        val configuration = if (profile.clientId.isEmpty()) {
            vpnClients.thisDeviceConfiguration(deployment, profile.protocol, label)
        } else {
            vpnClients.configuration(deployment, profile.protocol, profile.clientId)
        } ?: return null
        return profile.copy(
            device = configuration.fileName,
            configuration = configuration.text,
            serverId = deployment.id,
        )
    }

    /** Jobs a server reports get notifications with a Stop */
    private fun followServerJobs() {
        val notices = com.skaymer.gryonixnexus.app.notify.ServerJobNotices
        val relays = com.skaymer.gryonixnexus.app.notify.RelayServers
        fun deployment(serverId: String) = relays.target(store, serverId)?.let { (id, host) ->
            fleet.deployments.value.firstOrNull { it.id == id }?.let { it to (host ?: it.servicesHost) }
        }
        notices.store = store
        notices.serverName = { deployment(it)?.first?.name }
        notices.canceller = { serverId, job ->
            val (server, host) = deployment(serverId) ?: error("unknown server")
            com.skaymer.gryonixnexus.agentcontrol.AgentJobOperations(agents.client(server, host)).cancel(job)
        }
    }

    private fun createAgentTools() {
        notify = com.skaymer.gryonixnexus.app.notify.NotifyViewModel(
            scope = background,
            client = { agents.client(it) },
            release = { sessions.release(it.id) },
            store = store,
            pushToken = { relay -> pushToken(relay) },
            appVersion = packageManager.getPackageInfo(packageName, 0).versionName.orEmpty(),
            locale = java.util.Locale.getDefault().language,
            cachedToken = {
                getSharedPreferences(com.skaymer.gryonixnexus.app.push.GryonixMessagingService.PREFERENCES, Context.MODE_PRIVATE)
                    .getString(com.skaymer.gryonixnexus.app.push.GryonixMessagingService.TOKEN_KEY, null)
            },
            appKey = { AppIdentities(secrets).publicKey(it.id) },
            deviceProof = { com.skaymer.gryonixnexus.app.notify.DevicePushProof(secrets).proof },
            hostClient = { deployment, host -> agents.client(deployment, host) },
        )
        alertActions = com.skaymer.gryonixnexus.app.notify.AlertActionRunner(
            store = store,
            deployments = { fleet.deployments.value },
            client = { deployment, host -> agents.client(deployment, host) },
        )
        followServerJobs()
        dynamicDNS = DynamicDNSViewModel(
            scope = background,
            operations = { deployment ->
                AgentDynamicDNSOperations(
                    client = agents.client(deployment),
                    gate = agents.gate(deployment),
                )
            },
            release = { sessions.release(it.id) },
        )
        vaultwardenTwoFactor = com.skaymer.gryonixnexus.app.servers.VaultwardenTwoFactorViewModel(
            scope = background,
            operations = { deployment ->
                com.skaymer.gryonixnexus.agentcontrol.AgentVaultwardenOperations(
                    client = agents.client(deployment),
                    gate = agents.gate(deployment),
                )
            },
        )
        hostSecurity = SecurityViewModel(
            scope = background,
            operations = { deployment ->
                AgentSecurityOperations(
                    client = agents.client(deployment),
                    gate = agents.gate(deployment),
                )
            },
            release = { sessions.release(it.id) },
            publicKey = { AppIdentities(secrets).publicKey(it.id) },
            runner = { sessions.runner(it) },
            detached = { sessions.detached(it) },
            onDeploymentUpdated = { fleet.update(it) },
            invalidate = { sessions.disconnect(it.id) },
        )
    }

    private fun createMailTools() {
        mailboxes = MailboxesViewModel(
            scope = background,
            mailboxes = { deployment ->
                val hasEngine = MailboxesViewModel.hasEngine(deployment)
                when (MailboxRouting.route(
                    usesAgent = deployment.usesAgent,
                    agentTransportAvailable = true,
                    hasEngine = hasEngine,
                )) {
                    ServiceControlRoute.AGENT -> AgentMailboxOperations(
                        client = agents.client(deployment),
                        engineInstalled = hasEngine,
                        gate = agents.gate(deployment),
                    )
                    ServiceControlRoute.SSH -> MailboxOperations(
                        sessions.runner(deployment),
                        deployment,
                    )
                }
            },
            savePassword = { deployment, address, password ->
                val entry = com.skaymer.gryonixnexus.app.mail.MailboxVault.entry(
                    deployment, address, password, System.currentTimeMillis(), deviceIdentity.uid,
                )
                AgentVaultOperations(agents.client(deployment), agents.gate(deployment), deviceIdentity.uid)
                    .save(listOf(entry))
            },
            release = { sessions.release(it.id) },
        )
        addService = AddServiceViewModel(
            scope = background,
            installs = { deployment, service, context, onChunk ->
                AgentInstallOperations(
                    client = agents.client(deployment, deployment.agentHost(service)),
                    gate = agents.gate(deployment),
                ).install(service, context, onChunk = onChunk)
            },
            contexts = { deployment, service -> serviceSurfaceContext(deployment, service) },
            installedOnHost = { deployment ->
                AgentServiceMapping.serviceIDsForServices(
                    agents.client(deployment, deployment.vpnHost).getState().services.map { service ->
                        service.id to service.containers.map { it.name }
                    }
                )
            },
            persist = { fleet.update(it) },
            release = { sessions.release(it.id) },
            afterInstall = { deployment, service, portsChanged -> afterAddingService(deployment, service, portsChanged) },
            beforeInstall = { deployment, service ->
                if (service.id != ServiceID.CLOUDFLARED) emptyMap()
                else mapOf(AgentInstallSettings.CLOUDFLARED_TOKEN_KEY to tunnelSetup().connectorToken(deployment))
            },
            plans = { deployment, requests, purpose, onService, onChunk ->
                val (vpn, rest) = VPNRelayRouting.splitForRelay(requests, deployment.vpnRunsOnRelay) { it.first }
                val done = mutableSetOf<ServiceID>()
                if (rest.isNotEmpty()) done += runPlan(deployment, rest, purpose, null, onService, onChunk)
                if (vpn.isNotEmpty()) done += runPlan(deployment, vpn, purpose, deployment.vpnHost, onService, onChunk)
                done
            },
            installAgent = { deployment, onChunk ->
                ensureSudo(deployment, allowing = AgentBootstrapSections.SCRIPT_PATH)
                AgentBootstrapOperations.install(
                    runner = sessions.runner(deployment),
                    files = SSHJFileBrowser(sessions.runner(deployment)),
                    host = deployment.servicesHost,
                    sources = { assets.open("agent-src.bin").use { it.readBytes() } },
                    onPhase = { line -> onChunk("$line\n") },
                    onOutput = { line -> onChunk("$line\n") },
                )
                deployment
            },
        )
    }

    /** Runs one plan on one machine; what it installed */
    private suspend fun runPlan(
        deployment: Deployment,
        requests: List<Pair<ServiceID, AgentInstallContext>>,
        purpose: com.skaymer.gryonixnexus.agentcontrol.AgentPlanPurpose,
        host: com.skaymer.gryonixnexus.servercontrol.SSHHostID?,
        onService: (String) -> Unit,
        onChunk: (String) -> Unit,
    ): Set<ServiceID> {
        val operations = AgentInstallOperations(client = agents.client(deployment, host), gate = agents.gate(deployment))
        val started = operations.startPlan(requests, purpose)
        followedPlans += started.id
        val plan = try {
            followThroughDrops(deployment, started, onService, onChunk, host)
        } finally {
            followedPlans -= started.id
        }
        return requests.map { it.first }.filter { id ->
            plan.items.any {
                it.state == com.skaymer.gryonixnexus.agentcontrol.AgentInstallPlan.State.DONE &&
                    it.agentServiceID == AgentServiceMapping.agentID(id)
            }
        }.toSet()
    }

    /** Plans an add or repair screen follows itself */
    private val followedPlans: MutableSet<String> = java.util.concurrent.ConcurrentHashMap.newKeySet()

    /** Follows a plan again after the line drops */
    private suspend fun followThroughDrops(
        deployment: Deployment,
        started: com.skaymer.gryonixnexus.agentcontrol.AgentInstallPlan,
        onService: (String) -> Unit,
        onChunk: (String) -> Unit,
        host: com.skaymer.gryonixnexus.servercontrol.SSHHostID? = null,
    ): com.skaymer.gryonixnexus.agentcontrol.AgentInstallPlan {
        val mark = AgentInstallOperations.PlanLogMark()
        var drops = 0
        while (true) {
            try {
                val operations = AgentInstallOperations(client = agents.client(deployment, host), gate = agents.gate(deployment))
                return operations.followPlan(started, onService, { _, _ -> }, onChunk, mark = mark)
            } catch (error: Exception) {
                if (error is kotlinx.coroutines.CancellationException || error is com.skaymer.gryonixnexus.agentclient.AgentError.Rpc ||
                    error is AgentInstallOperations.PlanLost || drops++ >= PLAN_RECONNECTS
                ) throw error
                kotlinx.coroutines.delay(PLAN_RECONNECT_DELAY_MS)
                sessions.release(deployment.id)
            }
        }
    }

    private suspend fun ensureSudo(deployment: Deployment, allowing: String? = null) {
        val runner = sessions.runner(deployment)
        SudoReadiness.ensure(
            runner = runner,
            files = SSHJFileBrowser(runner),
            host = deployment.servicesHost,
            username = deployment.entry.user,
            prompter = sudoPrompter,
            allowing = allowing,
        )
    }

    private fun createServiceMove() {
        serviceMove = com.skaymer.gryonixnexus.app.servers.ServiceMoveViewModel(
            scope = background,
            machine = { deployment, node ->
                com.skaymer.gryonixnexus.agentcontrol.AgentServiceMoveMachine(
                    client = agents.client(deployment, node.sshHost),
                    shell = com.skaymer.gryonixnexus.agentcontrol.SSHMoveShell(
                        runner = sessions.runner(deployment),
                        host = node.sshHost,
                        loginUser = deployment.entry.user,
                    ),
                )
            },
            context = { deployment, route -> moveInstallContext(deployment, route) },
            persist = { fleet.update(it) },
            records = com.skaymer.gryonixnexus.app.servers.ServiceMoveRecords(
                getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE),
            ),
            release = { sessions.release(it.id) },
        )
    }

    private fun createServiceTools() {
        createServiceMove()
        serviceRemoval = ServiceRemovalViewModel(
            scope = background,
            removals = { deployment, service ->
                when (ServiceRemovalRouting.route(
                    scope = RemovalScope.SERVICE,
                    usesAgent = deployment.usesAgent,
                    agentTransportAvailable = true,
                )) {
                    ServiceControlRoute.AGENT -> AgentServiceRemoval(
                        client = agents.client(deployment, deployment.agentHost(service.id)),
                        gate = agents.gate(deployment),
                    )
                    ServiceControlRoute.SSH -> SSHServiceRemoval(
                        sessions.runner(deployment),
                        deployment,
                    )
                }
            },
            refreshHostSurface = { deployment ->
                AgentInstallOperations(
                    client = agents.client(deployment),
                    gate = agents.gate(deployment),
                ).provisionHost(hostSurfaceContext(deployment))
                if (deployment.hasRelayIngress) reprovisionRelay(deployment)
            },
            persist = { fleet.update(it) },
            release = { sessions.release(it.id) },
            agentTransportAvailable = true,
            unpublish = { deployment, service, after ->
                servicePublisher().pendingRemove(service, deployment, after)?.let { dnsUpdate.value = it }
                emptyList()
            },
            keepVPNProtocols = { deployment, left, onChunk ->
                val planned = deployment.copy(services = deployment.services.filterNot {
                    it in ServiceID.VPN_PROTOCOLS && it !in left
                }.toSet())
                installVPNProtocols(planned, left, onChunk)
            },
        )
        serviceLogs = ServiceLogsViewModel(
            scope = background,
            streams = { deployment, agentServiceID ->
                flow {
                    emitAll(
                        AgentServiceLogs(agents.client(deployment, VPNRelayRouting.logsHost(deployment, agentServiceID))).logs(
                            agentServiceID,
                            ServiceLogsViewModel.TAIL,
                        )
                    )
                }
            },
            snapshots = { deployment, service ->
                ServiceOperations(sessions.runner(deployment), deployment, service).logs()
            },
            agentTransportAvailable = true,
        )
        files = FileBrowserViewModel(
            scope = background,
            browsers = { SSHJFileBrowser(sessions.runner(it)) },
            startFolder = { ServerAccessStore.options(store, it.id).sftpDirectory },
            release = { sessions.release(it.id) },
        )
    }

    private fun createVPNMove() {
        vpnMove = VPNMoveViewModel(
            scope = background,
            machine = { deployment, host ->
                com.skaymer.gryonixnexus.app.vpn.AgentVPNMoveMachine(agents.client(deployment, host), agents.gate(deployment))
            },
            installVPN = { deployment ->
                installVPNProtocols(deployment, deployment.services.intersect(ServiceID.VPN_PROTOCOLS)) {}
            },
            reprovisionRelay = { reprovisionRelay(it) },
            persist = { fleet.update(it) },
            release = { sessions.release(it.id) },
            text = VPNMoveText(
                movingToRelay = getString(R.string.vpn_move_to_relay_title),
                movingHome = getString(R.string.vpn_move_home_title),
                packing = getString(R.string.vpn_move_packing),
                starting = getString(R.string.vpn_move_starting),
                doneOnRelay = getString(R.string.vpn_move_done_relay),
                doneAtHome = getString(R.string.vpn_move_done_home),
                packed = { getString(R.string.vpn_move_packed, it) },
                relayFailed = { getString(R.string.vpn_move_relay_failed, it) },
                oldCopyRunning = { getString(R.string.vpn_move_old_copy, it) },
                noSecondMachine = getString(R.string.vpn_move_no_relay),
                nothingToMove = getString(R.string.vpn_move_nothing),
            ),
        )
    }

    private fun createAgentViews() {
        createVPNMove()
        mesh = MeshViewModel(
            scope = background,
            operations = { deployment ->
                AgentMesh(
                    AgentMeshOperations(
                        client = agents.client(deployment),
                        gate = agents.gate(deployment),
                    )
                )
            },
            release = { sessions.release(it.id) },
        )
        vpnClients = VPNClientsViewModel(
            scope = background,
            operations = { deployment ->
                AgentVPNClients(
                    AgentVPNClientOperations(
                        client = agents.client(deployment, deployment.vpnHost),
                        gate = agents.gate(deployment),
                    )
                )
            },
            release = { sessions.release(it.id) },
            ownDevices = OwnVpnDevices.stored(getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)),
            notices = VPNClientNotices(getString(R.string.vpn_device_added), getString(R.string.vpn_device_removed), getString(R.string.dns_changed)),
            localMemory = com.skaymer.gryonixnexus.app.vpn.LocalDNSMemory.stored(getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)),
        )
        containers = ContainersViewModel(
            scope = background,
            operations = { deployment ->
                AgentContainers(
                    AgentContainerOperations(
                        client = agents.client(deployment),
                        gate = agents.gate(deployment),
                    )
                )
            },
            release = { sessions.release(it.id) },
        )
        access = AccessViewModel(
            scope = background,
            reports = { InstallReportStore(secrets, it.id) },
            credentials = { AccessCredentialStore(secrets, it.id) },
            import = InstallReportImport(
                runners = { sessions.runner(it) },
                reports = { InstallReportStore(secrets, it.id) },
                onDomainFound = { deployment, domain -> fleet.adoptDomain(deployment, domain) },
            ),
            vault = { deployment ->
                if (!deployment.usesAgent) null
                else AgentVaultOperations(
                    client = agents.client(deployment),
                    gate = agents.gate(deployment),
                    deviceUID = deviceIdentity.uid,
                )
            },
            deviceUID = { deviceIdentity.uid },
            release = { sessions.release(it.id) },
        )
    }

    private fun createVaultViews() {
        modelKeys = ModelKeysViewModel(
            scope = background,
            vault = { deployment ->
                if (!deployment.usesAgent) null
                else AgentVaultOperations(
                    client = agents.client(deployment),
                    gate = agents.gate(deployment),
                    deviceUID = deviceIdentity.uid,
                )
            },
            deviceUID = { deviceIdentity.uid },
            release = { sessions.release(it.id) },
        )
        localModels = LocalModelsViewModel(
            scope = background,
            client = { deployment ->
                if (!deployment.usesAgent) null else agents.client(deployment)
            },
            release = { sessions.release(it.id) },
        )
        mods = ModsViewModel(
            scope = background,
            operations = { deployment ->
                if (!deployment.usesAgent) null
                else AgentModOperations(agents.client(deployment), agents.gate(deployment))
            },
            release = { sessions.release(it.id) },
        )
        devices = DevicesViewModel(
            scope = background,
            operations = { AgentDeviceOperations(agents.client(it), agents.gate(it)) },
            thisDeviceUID = { deviceIdentity.uid },
            enrol = { deployment ->
                val uid = deviceIdentity.uid
                check(uid.isNotBlank()) { "Could not read this device's identity" }
                val key = AppIdentities(secrets).publicKey(deployment.id)
                val result = sessions.runner(deployment).run(
                    com.skaymer.gryonixnexus.app.servers.AdoptViewModel.PAIR_CODE_COMMAND,
                    deployment.servicesHost,
                    kotlin.time.Duration.parse("30s"),
                )
                check(result.succeeded) { "Could not obtain a pairing code from the server" }
                val code = com.skaymer.gryonixnexus.agentclient.PairingCode.parse(result.stdout)
                    ?: error("The server returned no pairing code")
                agents.client(deployment).pair(code, key, android.os.Build.MODEL, uid)
            },
            release = { sessions.release(it.id) },
        )
        installs = InstallRegistry(
            scope = background,
            sessions = InstallSessions(secrets),
            reports = { InstallReportStore(secrets, it.id) },
            agent = InstallRegistry.Agent(
                sessions = agents,
                sources = { assets.open("agent-src.bin").use { it.readBytes() } },
                context = { hostSurfaceContext(it) },
                persistUsesAgent = { deployment ->
                    if (!deployment.usesAgent) fleet.update(deployment.copy(usesAgent = true))
                },
                tunnel = tunnelSetup(),
            ),
        )
    }

    private companion object {
        const val PREFERENCES = "gryonixnexus.settings"

        const val SECRETS = "gryonixnexus.secrets"

        const val PLAN_RECONNECTS = 5

        const val PLAN_RECONNECT_DELAY_MS = 3_000L
    }

    /** Starts Firebase from the relay and asks for a token */
    private suspend fun pushToken(relayUrl: String): String {
        val settings = com.skaymer.gryonixnexus.app.push.RelayFirebase.settings(relayUrl)
            ?: error(getString(com.skaymer.gryonixnexus.R.string.push_relay_has_no_android))
        return com.skaymer.gryonixnexus.app.push.RelayFirebase.token(this, settings)
    }
}
