import AgentClient
import SwiftUI
import VPNTunnel

@main
struct gryonixNexusApp: App {
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    #else
    @NSApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    #endif
    #if os(macOS)
    /// Status changes only, so the scenes skip traffic ticks
    @ObservedObject private var tunnelMark = TunnelStatusMark.shared
    @State private var menuBarItemShown = MenuBarSettings.shared.showsItem
    #endif

    init() {
        #if DEBUG
        PermissionsOnboardingModifier.resetIfAsked()
        #if os(iOS)
        FrameProbe.startIfAsked()
        IconDriftProbe.startIfAsked()
        #endif
        #endif
        ConfiguratorStore.shared.clearDrafts()
        ServerSessionWarmup.start()
        DemoServer.forgetInWidgets()
        ServerControlIntents.openServer = { AppNavigator.shared.openServer($0) }
        #if os(iOS)
        OperationIntents.retry = { id in RunningOperationsRegistry.shared.retry(cardOf: id) }
        OperationIntents.stop = { id in await OperationStopper.shared.tapped(id) }
        OperationIntents.stopJob = { job, server in await OperationStopper.shared.tappedJob(job, server: server) }
        LiveActivityStarts.shared.begin()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            SplashGate {
                RootTabView()
                    .permissionsOnboarding()
            }
            .appAccentTint()
            .buttonStyle(HapticButtonStyle())
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .onChange(of: scenePhase) { _, phase in handle(phase) }
            .task { OperationActivities.shared.endOrphans() }
            .task { PurchaseStore.shared.start() }
            .licensePromptHost()
            #if DEBUG
            .task { if DemoVPNSession.isAsked { await DemoVPNSession.start() } }
            .task { await LiveActivityProbe.runBurst() }
            .task { await probeOperationCard() }
            #endif
            .onOpenURL { url in
                if url.isFileURL, url.pathExtension == DeploymentTransferService.fileExtension {
                    AppNavigator.shared.openServerFile(url)
                    return
                }
                if PairApproval.shared.handle(url) { return }
                guard let destination = AppLink.destination(of: url) else { return }
                AppNavigator.shared.open(destination)
            }
            #if os(macOS)
            .onChange(of: menuBarItemShown) { _, newValue in
                guard MenuBarSettings.shared.showsItem != newValue else { return }
                MenuBarSettings.shared.showsItem = newValue
            }
            .onReceive(MenuBarSettings.shared.$showsItem) { newValue in
                guard menuBarItemShown != newValue else { return }
                menuBarItemShown = newValue
            }
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        // ⌘, for settings and ⌘1…⌘9 for the sections — see `AppCommands`.
        .commands { AppCommands() }
        #endif

        #if os(macOS)
        MenuBarExtra(isInserted: $menuBarItemShown) {
            MenuBarVPNView(tunnel: TunnelController.shared)
        } label: {
            TunnelPresentation.menuBarMark(tunnelMark.status, size: 18)
        }
        .menuBarExtraStyle(.window)
        #endif
    }

    private func handle(_ phase: ScenePhase) {
        RunningJobsWatcher.shared.isAppActive = phase == .active
        if phase == .background { MetricPanelStore.shared.flush() }
        #if os(iOS)
        if phase == .background { IslandAwayCheck.leaving() }
        if phase == .active { IslandAwayCheck.back() }
        #endif
        if phase == .active { Task { await RunningJobsWatcher.shared.sweep() } }
        if phase == .active { Task { await NotifyFleetSync.shared.refreshTokenIfAllowed() } }
        if phase == .active { Task { await LicenseStore.shared.refreshIfDue() } }
        if phase == .active { CloudSync.shared.scheduleSync(after: 0) }
        #if os(iOS)
        if phase == .active { Task { await AppleTVLink.shared.vouchAll() } }
        #endif
    }

    #if DEBUG
    /// Gives the demo failure a refusal reason
    private static func rememberDemoRefusal(message: String) {
        guard let spec = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_LIVE_FAIL_REASON"] else { return }
        let parts = spec.split(separator: "|").map(String.init)
        guard let reason = parts.first else { return }
        AgentRefusals.shared.remember(AgentRefusal(reason: reason, args: Array(parts.dropFirst()), message: message))
    }

    private func probeOperationCard() async {
        guard LiveActivityProbe.isEnabled else { return }
        let run = LongOperationState(title: UIL10n.string("Updating %@", "Nextcloud"),
                                     progressText: "Pulling images…")
        RunningOperationsRegistry.shared.start(run, serverName: "probe.example.com")
        for step in 1...4 {
            try? await Task.sleep(for: .seconds(3))
            run.progressText = "step \(step) of 4"
            run.progress = Double(step) / 4
            OperationActivities.shared.noteSystemState()
        }
        try? await Task.sleep(for: .seconds(3))
        if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_LIVE_FAIL"] != nil {
            run.retry = {}
            Self.rememberDemoRefusal(message: "No space left on /var")
            run.errorMessage = "No space left on /var"
        } else {
            run.progressText = "Updated."
        }
        run.isFinished = true
    }
    #endif
}
