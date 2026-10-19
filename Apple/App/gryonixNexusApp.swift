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
    @ObservedObject private var tunnel = TunnelController.shared
    @State private var menuBarItemShown = MenuBarSettings.shared.showsItem
    #endif

    init() {
        #if DEBUG
        PermissionsOnboardingModifier.resetIfAsked()
        #if os(iOS)
        FrameProbe.startIfAsked()
        #endif
        #endif
        ConfiguratorStore.shared.clearDrafts()
        ServerSessionWarmup.start()
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
            .onChange(of: scenePhase) { _, phase in
                RunningJobsWatcher.shared.isAppActive = phase == .active
                if phase == .background { MetricPanelStore.shared.flush() }
                if phase == .active { Task { await RunningJobsWatcher.shared.sweep() } }
                if phase == .active { Task { await NotifyFleetSync.shared.refreshTokenIfAllowed() } }
                if phase == .active { Task { await LicenseStore.shared.refreshIfDue() } }
            }
            .task { OperationActivities.shared.endOrphans() }
            .task { PurchaseStore.shared.start() }
            .licensePromptHost()
            #if DEBUG
            .task { if DemoVPNSession.isAsked { await DemoVPNSession.start() } }
            .task { await LiveActivityProbe.runBurst() }
            .task {
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
                    run.errorMessage = "No space left on /var"
                } else {
                    run.progressText = "Updated."
                }
                run.isFinished = true
            }
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
            MenuBarVPNView(tunnel: tunnel)
        } label: {
            TunnelPresentation.menuBarMark(tunnel.status, size: 18)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}
