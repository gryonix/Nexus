package com.skaymer.gryonixnexus.app

import android.content.Intent
import android.os.Bundle
import com.skaymer.gryonixnexus.app.notify.AlertAction
import com.skaymer.gryonixnexus.app.notify.AlertTap
import com.skaymer.gryonixnexus.app.notify.AlertDestination
import com.skaymer.gryonixnexus.app.notify.RelayServers
import com.skaymer.gryonixnexus.app.push.GryonixMessagingService
import com.skaymer.gryonixnexus.app.shell.ServerSection
import com.skaymer.gryonixnexus.app.widgets.AppShortcuts
import com.skaymer.gryonixnexus.app.widgets.ShortcutTarget
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import com.skaymer.gryonixnexus.app.security.BiometricGate
import com.skaymer.gryonixnexus.app.security.LocalDeviceGate
import com.skaymer.gryonixnexus.app.security.LocalSecuritySettings
import com.skaymer.gryonixnexus.app.shell.Haptics
import com.skaymer.gryonixnexus.app.shell.appAccent
import com.skaymer.gryonixnexus.app.shell.hapticsEnabled
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.skaymer.gryonixnexus.app.ui.SudoPasswordDialog
import com.skaymer.gryonixnexus.app.ui.AppShell
import com.skaymer.gryonixnexus.app.ui.PermissionsOnboardingGate
import androidx.compose.ui.platform.LocalView
import com.skaymer.gryonixnexus.app.metrics.ChartScale
import com.skaymer.gryonixnexus.app.metrics.OfferedCharts
import com.skaymer.gryonixnexus.app.ui.LocalChartAutoScale
import com.skaymer.gryonixnexus.app.ui.design.LocalHaptics
import com.skaymer.gryonixnexus.app.ui.LocalOfferedCharts
import com.skaymer.gryonixnexus.app.ui.design.GryonixTheme
import com.skaymer.gryonixnexus.app.ui.design.SystemBarsFollowTheme
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as GryonixApplication
        followMetricsWhileStarted(app)
        setContent { AppRoot(app, this) }
        openTappedAlert(intent)
        openShortcut(intent)
        recordOpenedServers(app)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        openTappedAlert(intent)
        openShortcut(intent)
    }

    /** Opens the section or server a shortcut asks for */
    private fun openShortcut(intent: Intent?) {
        val app = application as GryonixApplication
        when (val target = ShortcutTarget.of(intent)) {
            is ShortcutTarget.Tab -> app.navigator.show(target.tab)
            is ShortcutTarget.Server -> app.navigator.open(target.id, ServerSection.GENERAL)
            null -> return
        }
        intent?.action = null
    }

    /** Keeps the launcher's server shortcuts on the servers opened last */
    private fun recordOpenedServers(app: GryonixApplication) {
        val shortcuts = AppShortcuts(this)
        lifecycleScope.launch {
            app.navigator.openServerID.collect { id ->
                if (id == null) shortcuts.publish() else shortcuts.opened(id)
            }
        }
    }

    /** Opens the server a tapped alert is about */
    private fun openTappedAlert(intent: Intent?) {
        val gnx = intent?.getStringExtra(GryonixMessagingService.EXTRA_ALERT) ?: return
        intent.removeExtra(GryonixMessagingService.EXTRA_ALERT)
        val app = application as GryonixApplication
        val tap = AlertTap.of(
            AlertAction.data(gnx),
            intent.getStringExtra(GryonixMessagingService.EXTRA_ALERT_TITLE),
            intent.getStringExtra(GryonixMessagingService.EXTRA_ALERT_BODY),
        ) { RelayServers.target(app.store, it)?.first }
        tap.jobID?.let { job ->
            app.runningJobs.open(job)
            tap.destination?.let { app.runningJobs.adoptNamed(job, it.deploymentID) }
            app.runningJobs.sweep()
        }
        val destination = tap.destination ?: return
        app.navigator.open(destination.deploymentID, destination.section, destination.service, tap.card)
    }

    private fun followMetricsWhileStarted(app: GryonixApplication) {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                app.metrics.resume(app.fleet.deployments.value)
                app.runningJobs.sweep()
                app.agentUpdateOffer.checkOnLaunch()
                launch { app.license.refreshIfDue() }
                launch { app.appleTv.vouchAll() }
                try {
                    awaitCancellation()
                } finally {
                    app.metrics.stopAll()
                    app.agentUpdateOffer.appLeft()
                }
            }
        }
    }
}

@Composable
private fun AppRoot(app: GryonixApplication, activity: ComponentActivity) {
    val revision by app.store.revision.collectAsState()
    val accent = remember(revision) { app.store.appAccent() }
    val updateScope = rememberCoroutineScope()
    LaunchedEffect(Unit) { app.appUpdates.checkIfDue(updateScope) }
    SystemBarsFollowTheme(activity)
    GryonixTheme(accent = accent) {
        val autoScale = remember(revision) {
            ChartScale.auto(app.store.boolean(ChartScale.AUTO_KEY))
        }
        val offered = remember(revision) { OfferedCharts.of(app.store) }
        val view = LocalView.current
        val hapticsOn = remember(revision) { app.store.hapticsEnabled() }
        val player: (Haptics.Feel) -> Unit = remember(view, hapticsOn) {
            { feel -> if (hapticsOn) view.performHapticFeedback(Haptics.constant(feel)) }
        }
        CompositionLocalProvider(
            LocalDeviceGate provides BiometricGate(activity),
            LocalSecuritySettings provides app.security,
            LocalChartAutoScale provides autoScale,
            LocalOfferedCharts provides offered,
            LocalHaptics provides player,
        ) {
            PermissionsOnboardingGate(app.store) { AppShellFor(app) }
            SudoPasswordDialog(app.sudoPrompter)
            com.skaymer.gryonixnexus.app.ui.AgentUpdateOfferDialog()
            com.skaymer.gryonixnexus.app.ui.DNSUpdateDialog()
        }
    }
}

@Composable
private fun AppShellFor(app: GryonixApplication) {
    AppShell(
        tabs = app.tabs,
        sections = app.sections,
        store = app.store,
        fleet = app.fleet,
        navigator = app.navigator,
        configurator = app.configurator,
        secrets = app.secrets,
        check = app.connectionCheck,
        metrics = app.metrics,
        history = app.history,
        board = app.metricsBoard,
        panels = app.metricPanels,
        services = app.services,
        updates = app.updates,
        appUpdates = app.appUpdates,
        backups = app.backups,
        mesh = app.mesh,
        access = app.access,
        devices = app.devices,
        installs = app.installs,
        vpnClients = app.vpnClients,
        vpnTunnel = app.vpnTunnel,
        containers = app.containers,
        erase = app.erase,
        transfer = app.transfer,
        hostActions = app.hostActions,
        wakeOnLAN = app.wakeOnLAN,
        files = app.files,
        serviceLogs = app.serviceLogs,
        serviceRemoval = app.serviceRemoval,
        serviceMove = app.serviceMove,
        addService = app.addService,
        mailboxes = app.mailboxes,
        modelKeys = app.modelKeys,
        localModels = app.localModels,
        mods = app.mods,
        dynamicDNS = app.dynamicDNS,
        security = app.hostSecurity,
        shellUsers = app.shellUsers,
        agentRemoval = app.agentRemoval,
        systemUpdates = app.systemUpdates,
        hostProbes = app.hostProbes,
        addMachine = app.addMachine,
        dkim = app.dkim,
        welcome = app.welcome,
        terminals = app.terminals,
        agentInstall = app.agentInstall,
        agentSelfUpdate = app.agentSelfUpdate,
        cloudflare = app.cloudflare,
        relayStatus = app.relayStatus,
        dnsCredentials = app.dnsCredentials,
        terminalHosts = app.terminalHosts,
        adopt = app.adopt,
        runningJobs = app.runningJobs,
        onForget = { app.forget(it) },
    )
}
