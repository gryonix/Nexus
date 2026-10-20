import SwiftUI
import ServiceCatalog
import ServerControl

/// Top-level app shell: server dashboard + config generator + settings
struct RootTabView: View {
    @StateObject private var tabs = TabBarSettings.shared
    @StateObject private var navigator = AppNavigator.shared
    @StateObject private var agentUpdate = AgentUpdateOffer.shared
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var operations = RunningOperationsRegistry.shared
    @State private var selection: AppTab?
    @State private var moreIsActive = false
    @StateObject private var overflow = ShellOverflow.shared
    @StateObject private var tunnel = TunnelController.shared
    @State private var showingWelcome = false
    @State private var welcomeChoseConfigure = false
    @StateObject private var tour = AppTour.shared
    @AppStorage(PermissionsOnboardingModifier.shownKey) private var permissionsShown = false
    @AppStorage(AppAccentSettings.choiceKey)
    private var accentRaw = AppAccentSettings.storedChoice().rawValue
    @AppStorage(AppIconSettings.choiceKey)
    private var iconRaw = AppIconChoice.default.rawValue
    /// Where metrics live
    @AppStorage(MetricsDisplaySettings.placementKey)
    private var placementRaw = MetricsPlacement.both.rawValue
    @AppStorage(VPNDisplaySettings.placementKey)
    private var vpnPlacementRaw = VPNPlacement.both.rawValue
    @AppStorage(ContainersDisplaySettings.placementKey)
    private var containersPlacementRaw = ContainersPlacement.server.rawValue
    @AppStorage(TerminalDisplaySettings.placementKey)
    private var terminalPlacementRaw = TerminalPlacement.server.rawValue

    private var visibleTabs: [AppTab] {
        ShellSections.visible(order: tabs.visibleTabs,
                              metricsRaw: placementRaw,
                              vpnRaw: vpnPlacementRaw,
                              containersRaw: containersPlacementRaw,
                              terminalRaw: terminalPlacementRaw)
    }

    var body: some View {
        installSheets(welcome(routing(chrome)))
    }

    private var chrome: some View {
        shell
            #if os(iOS)
            .tabBarLongPressMenu()
            #endif
            .brandPill()
            .sheet(item: $operations.presented) { operation in
                LongOperationSheet(
                    operation: operation,
                    downloadBackup: operations.downloadBackup(for: operation)) {
                        operations.dismissPresented()
                    }
            }
            .task { applyStartTab() }
            #if os(iOS)
            .overlay { AppTourOverlay(tour: tour, onConfigure: openConfigurator) }
            #else
            .overlay { AppTourMacOverlay(tour: tour) }
            #endif
    }

    private func openConfigurator() {
        guard visibleTabs.contains(.configurator) else { return }
        selection = .configurator
    }

    private func applyStartTab() {
        #if DEBUG
        if applyDebugStartTab() { return }
        #endif
        if selection == nil { selection = tabs.effectiveStartTab }
    }

    #if DEBUG
    private static let demoTabsBeforeSections: [(String, AppTab)] = [
        ("GRYONIXNEXUS_DEMO_OPEN_METRICS", .metrics),
        ("GRYONIXNEXUS_DEMO_OPEN_APPEARANCE", .settings),
        ("GRYONIXNEXUS_DEMO_OPEN_SETTINGS", .settings),
        ("GRYONIXNEXUS_DEMO_OPEN_PROXIES", .settings),
        ("GRYONIXNEXUS_DEMO_OPEN_WIDGETS", .settings),
    ]

    private static let demoTabsAfterSections: [(String, AppTab)] = [
        ("GRYONIXNEXUS_DEMO_OPEN_CONTAINERS", .containers),
        ("GRYONIXNEXUS_DEMO_OPEN_TERMINAL", .terminal),
        ("GRYONIXNEXUS_DEMO_OPEN_VPN", .vpn),
        ("GRYONIXNEXUS_DEMO_OPEN_CONFIGURATOR", .configurator),
    ]

    private func applyDebugStartTab() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["GRYONIXNEXUS_DEBUG_DKIM"] != nil || environment["GRYONIXNEXUS_DEBUG_LOCALONLY"] != nil {
            selection = .configurator
            return true
        }
        if InstallResetProbe.autoDrive {
            WelcomeState.markShown()
            selection = .configurator
            return true
        }
        InstallResetProbe.forgetFleetIfAsked()
        if environment["GRYONIXNEXUS_DEBUG_REATTACH"] == "1" {
            WelcomeState.markShown()
            selection = .servers
            Task { await InstallResetProbe.seedReattachedInstall() }
            return true
        }
        if let tab = Self.demoTabsBeforeSections.first(where: { environment[$0.0] != nil })?.1 {
            selection = tab
            return true
        }
        if environment["GRYONIXNEXUS_DEMO_OPEN_SECTIONS"] != nil {
            AppNavigator.shared.showSettingsPage(.sections)
            return true
        }
        if let more = environment["GRYONIXNEXUS_DEMO_OPEN_MORE"] {
            moreIsActive = true
            overflow.current = AppTab(rawValue: more)
            return true
        }
        if let tab = Self.demoTabsAfterSections.first(where: { environment[$0.0] != nil })?.1 {
            selection = tab
            return true
        }
        return false
    }
    #endif

    private func routing(_ base: some View) -> some View {
        base
            .onReceive(navigator.$openServerID.compactMap { $0 }) { _ in
                navigator.resumeInstall = nil
                guard visibleTabs.contains(.servers) else {
                    navigator.openServerID = nil
                    return
                }
                selection = .servers
            }
            .onReceive(navigator.$requestedTab.compactMap { $0 }) { tab in
                navigator.requestedTab = nil
                guard visibleTabs.contains(tab) else { return }
                selection = tab
            }
            .onChange(of: selection) { _, tab in
                guard let tab, overflowTabs.contains(tab) else { return }
                overflow.current = tab
                moreIsActive = true
            }
            .onChange(of: overflowTabs, initial: true) { _, tabs in
                overflow.sections = tabs
                if let current = overflow.current, !tabs.contains(current) {
                    overflow.current = nil
                }
            }
            .onChange(of: visibleTabs) { _, visible in
                if let selection, !visible.contains(selection) {
                    self.selection = visible.first
                }
            }
    }

    private func welcome(_ base: some View) -> some View {
        base
            .sheet(isPresented: $showingWelcome, onDismiss: {
                if !welcomeChoseConfigure { tour.startIfDue() }
            }) {
                WelcomeSheet {
                    welcomeChoseConfigure = true
                    openConfigurator()
                }
            }
            .task {
                showWelcomeIfDue()
                #if DEBUG
                if let first = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_TOUR"] {
                    tour.start(at: AppTourStep.allCases.first { "\($0)" == first })
                }
                #endif
            }
            #if DEBUG
            .task { await switchTabsForProbe() }
            #endif
            .onChange(of: permissionsShown) { _, _ in showWelcomeIfDue() }
    }

    #if DEBUG
    private func switchTabsForProbe() async {
        guard let raw = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_SWITCH_TABS"] else { return }
        for tab in raw.split(separator: ",").compactMap({ AppTab(rawValue: String($0)) }) {
            try? await Task.sleep(for: .milliseconds(1500))
            #if os(iOS)
            FrameProbe.note("tab \(tab.rawValue)")
            #endif
            navigator.show(tab)
        }
    }
    #endif

    /// The welcome waits until the permissions screen is gone.
    private func showWelcomeIfDue() {
        #if DEBUG
        if DemoDeployments.fromEnvironment() != nil { return }
        if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_WELCOME"] != nil {
            WelcomeState.forget()
        }
        #endif
        guard permissionsShown || !PermissionsOnboardingModifier.appliesHere else { return }
        guard !WelcomeState.hasBeenShown else { return }
        WelcomeState.markShown()
        showingWelcome = true
    }

    private func installSheets(_ base: some View) -> some View {
        base
            .task { await agentUpdate.checkOnLaunch() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await agentUpdate.checkOnLaunch() } }
                if phase == .background { agentUpdate.appLeft() }
            }
            .sheet(item: $agentUpdate.offer) { offer in
                AgentUpdateOfferView(model: agentUpdate, offer: offer)
            }
            .sheet(item: $navigator.reinstallRequest) { request in
                ReinstallFlowView(request: request)
            }
            .sheet(item: $navigator.resumeInstall) { deployment in
                NavigationStack {
                    if let session = InstallSessionRegistry.shared.existingSession(for: deployment.id) {
                        InstallFlowView(session: session, isSheet: true)
                    } else {
                        ContentUnavailableView("Installation finished",
                                               systemImage: "checkmark.seal")
                        #if os(macOS)
                        .safeAreaInset(edge: .bottom) {
                            Button("Close") { navigator.resumeInstall = nil }
                                .controlSize(.large)
                                .padding()
                        }
                        #endif
                    }
                }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 520)
                #endif
            }
            .sheet(item: $navigator.reopenInstallResult) { deployment in
                NavigationStack {
                    ReattachedInstallResultView(deployment: deployment)
                }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 560)
                #endif
            }
    }

    private var barTabs: [AppTab] { ShellSections.onBar(visibleTabs) }

    private var overflowTabs: [AppTab] {
        tabs.barStyle == .custom ? [] : ShellSections.behindMore(visibleTabs)
    }

    private var overflowContent: AppTab? {
        overflow.current.flatMap { overflowTabs.contains($0) ? $0 : nil }
    }

    private enum ShellSelection: Hashable {
        case tab(AppTab)
        case more
    }

    private var shellSelection: Binding<ShellSelection> {
        Binding(
            get: {
                if moreIsActive, !overflowTabs.isEmpty { return .more }
                return .tab(current.wrappedValue)
            },
            set: { value in
                switch value {
                case .tab(let tab):
                    moreIsActive = false
                    selection = tab
                case .more:
                    overflow.current = nil
                    moreIsActive = true
                }
            }
        )
    }

    private var current: Binding<AppTab> {
        Binding(
            get: { selection.flatMap { visibleTabs.contains($0) ? $0 : nil } ?? visibleTabs.first ?? .settings },
            set: { selection = $0 }
        )
    }

    /// Bumped when a section is reselected on the custom bar
    @State private var reselectCounters: [AppTab: Int] = [:]

    @ViewBuilder
    private var shell: some View {
        #if os(iOS)
        if tabs.barStyle == .custom {
            customShell
        } else if #available(iOS 18.0, *) {
            TabView(selection: shellSelection) {
                ForEach(barTabs) { tab in
                    Tab(value: ShellSelection.tab(tab)) {
                        content(for: tab)
                    } label: {
                        Label { Text(tab.title) } icon: { tab.barIcon(tunnelActive: tunnel.status.isActive) }
                    }
                }
                if !overflowTabs.isEmpty {
                    Tab("More", systemImage: "ellipsis", value: ShellSelection.more) {
                        moreSlot
                    }
                }
            }
            .modifier(SidebarAdaptableOnPad())
            .modifier(BannerInTabBarAccessory())
            .modifier(SystemBarClearance())
            .modifier(SystemTabSlide(selection: shellSelection.wrappedValue))
        } else {
            TabView(selection: current) {
                ForEach(visibleTabs) { tab in
                    content(for: tab)
                        .tabItem {
                            Label { Text(tab.title) } icon: {
                                tab.barIcon(tunnelActive: tunnel.status.isActive)
                            }
                        }
                        .tag(tab)
                }
            }
            .modifier(SystemBarClearance())
            .modifier(SystemTabSlide(selection: current.wrappedValue))
        }
        #else
        MacSidebarShell(tabs: tabs, visibleTabs: visibleTabs, selection: current,
                        tunnelActive: tunnel.status.isActive)
        #endif
    }

    #if os(iOS)
    private var customShell: some View {
        GeometryReader { proxy in
            let side = SideTabRail.applies(to: proxy.size)
            customPages(bottomBar: !side)
                .overlay(alignment: .bottomTrailing) {
                    if side { sideRail(in: proxy) }
                }
        }
    }

    /// Sits in the trailing safe-area column, below the toolbar buttons
    private func sideRail(in proxy: GeometryProxy) -> some View {
        let column = proxy.safeAreaInsets.trailing
        let width = SideTabRail.width(column: column)
        return SideTabRail(tabs: visibleTabs, selection: current,
                           tunnelActive: tunnel.status.isActive,
                           selectedTint: CustomTabBar.selectedTint(accentRaw: accentRaw, iconRaw: iconRaw),
                           width: width,
                           onReselect: { tab in reselectCounters[tab, default: 0] += 1 })
            .appTourTarget(.sectionBar)
            .frame(maxHeight: proxy.size.height * 0.6, alignment: .bottom)
            .padding(.trailing, max(SideTabRail.gap, (column - width) / 2))
            .padding(.bottom, 8)
            .ignoresSafeArea(edges: .trailing)
    }

    private func customPages(bottomBar: Bool) -> some View {
        let active = current.wrappedValue
        let showsBar = bottomBar && overflow.screensOwningBottom == 0
        return SlidingPages(pages: visibleTabs, selection: active) { tab in
            content(for: tab)
        }
        .bottomBarClearanceEverywhere()
        .environment(\.barClearance, showsBar ? CustomTabBar.totalFootprint : 0)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                ActivityBanner(surface: .ownCapsule)
                    .padding(.horizontal, ActivityBanner.classicBarInset)
                if showsBar {
                    CustomTabBar(tabs: visibleTabs, selection: current,
                                 tunnelActive: tunnel.status.isActive,
                                 onReselect: { tab in reselectCounters[tab, default: 0] += 1 })
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: overflow.screensOwningBottom == 0)
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .environment(\.sectionReselectTicks, reselectCounters)
    }
    #endif

    @ViewBuilder private var moreSlot: some View {
        if let section = overflowContent {
            content(for: section)
        } else {
            MoreSectionsView(sections: overflowTabs) { overflow.current = $0 }
                .modifier(BannerAboveClassicTabBar())
        }
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        Group {
            switch tab {
            case .servers: ServerListView()
            case .containers: ContainersSection().licenseLocked(exceptDemo: true)
            case .metrics: MetricsDashboardView().licenseLocked(exceptDemo: true)
            case .vpn: VPNSectionView().licenseLocked(exceptDemo: true)
            case .terminal: TerminalSection().licenseLocked()
            case .configurator: AppRootView().licenseLocked(exceptDemo: true)
            case .settings: AppSettingsView()
            }
        }
        .modifier(BannerAboveClassicTabBar())
    }
}

private struct BannerInTabBarAccessory: ViewModifier {
    @ObservedObject private var pending = PendingAgentInstalls.shared
    @ObservedObject private var installs = InstallSessionRegistry.shared
    @ObservedObject private var operations = RunningOperationsRegistry.shared

    private var isIdle: Bool {
        pending.pending.isEmpty && installs.installing.isEmpty && operations.entries.isEmpty
    }

    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.1, *) {
            content.tabViewBottomAccessory(isEnabled: !isIdle) {
                ActivityBanner(surface: .systemProvided)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

private struct BannerAboveClassicTabBar: ViewModifier {
    @ObservedObject private var tabs = TabBarSettings.shared

    func body(content: Content) -> some View {
        #if os(iOS)
        if tabs.barStyle == .custom {
            content
        } else if #available(iOS 26.1, *) {
            content
        } else {
            content.safeAreaInset(edge: .bottom) {
                ActivityBanner(surface: .ownCapsule)
                    .padding(.horizontal, ActivityBanner.classicBarInset)
            }
        }
        #else
        content.safeAreaInset(edge: .bottom) {
                ActivityBanner().padding(.horizontal, ActivityBanner.classicBarInset)
            }
        #endif
    }
}

#if os(iOS)
/// Applies `.sidebarAdaptable` only where a sidebar can actually appear
@available(iOS 18.0, *)
private struct SidebarAdaptableOnPad: ViewModifier {
    func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            content.tabViewStyle(.sidebarAdaptable)
        } else {
            content
        }
    }
}
#endif

#if os(macOS)
/// macOS shell
private struct MacSidebarShell: View {
    @ObservedObject var tabs: TabBarSettings
    /// Already filtered by the metrics-placement setting — see RootTabView
    let visibleTabs: [AppTab]
    @Binding var selection: AppTab
    let tunnelActive: Bool
    @State private var editingSections = false

    init(tabs: TabBarSettings, visibleTabs: [AppTab], selection: Binding<AppTab>,
         tunnelActive: Bool) {
        self.tabs = tabs
        self.visibleTabs = visibleTabs
        _selection = selection
        self.tunnelActive = tunnelActive
    }

    var body: some View {
        NavigationSplitView {
            List(visibleTabs, selection: Binding(
                get: { Optional(selection) },
                set: {
                    if let new = $0 {
                        if new == .configurator {
                            DispatchQueue.main.async { AppNavigator.shared.resetConfigurator() }
                        }
                        selection = new
                    }
                }
            )) { tab in
                Label { Text(tab.title) } icon: { tab.barIcon(tunnelActive: tunnelActive) }
                    .tag(tab)
                    .contextMenu {
                        Button {
                            editingSections = true
                        } label: {
                            Label("Edit sections…", systemImage: "square.grid.2x2")
                        }
                    }
            }
            .appTourTarget(.sectionBar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
            .sheet(isPresented: $editingSections) {
                NavigationStack {
                    TabBarSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { editingSections = false }
                            }
                        }
                }
                .frame(minWidth: 420, minHeight: 380)
            }
        } detail: {
            Group {
                switch selection {
                case .servers: ServerListView()
                case .containers: ContainersSection().licenseLocked(exceptDemo: true)
                case .metrics: MetricsDashboardView().licenseLocked(exceptDemo: true)
                case .vpn: VPNSectionView().licenseLocked(exceptDemo: true)
                case .terminal: TerminalSection().licenseLocked()
                case .configurator: AppRootView().licenseLocked(exceptDemo: true)
                case .settings: AppSettingsView()
                }
            }
            .safeAreaInset(edge: .bottom) { ActivityBanner(surface: .ownCapsule) }
        }
    }
}
#endif

#Preview {
    RootTabView()
}
