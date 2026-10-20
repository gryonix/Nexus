import gryonixNexusCore
import ServerControl
import ServiceCatalog
import SwiftUI

struct DashboardView: View {
    let onUpdate: (Deployment) -> Void
    var onDelete: ((Deployment) -> Void)?

    @State private var dismiss = DismissHandle()
    @StateObject private var viewModel: DashboardViewModel
    @StateObject private var storage = StorageOverview()
    @State private var sudoPassword = ""
    @State private var showErase = false
    @State private var pendingErasePurge: PurgeOptions?
    @State private var showSettings = false
    @State private var showKeySheet = false
    /// Guards the "Repair server" re-run behind a confirmation
    @State private var showingDynamicDNS = false
    @State private var showingNotifications = false
    @State private var showAgent: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_AGENT"] != nil
        #else
        return false
        #endif
    }()
    @State private var confirmingRepair = false
    @State private var rerunning: PendingRerun?
    @State private var passphraseService: ServiceID?
    @State private var pendingEncryptedBackup: PendingEncryptedBackup?
    @State private var backupService: ServiceID?
    @State private var pendingBackup: PendingBackup?
    @State private var restoreService: ServiceID?
    @State private var pendingRestore: PendingRestore?
    @State private var confirmingRestore: PendingRestore?
    @AppStorage(SecuritySettings.gateAccessScreenKey) private var gateAccessScreen = true
    @State private var showAccessAndPasswords = false
    @Environment(\.scenePhase) private var scenePhase
    /// The glass strip's height, which the system picker matches
    @ScaledMetric(relativeTo: .subheadline) private var stripHeight: CGFloat = 44
    @State private var showConfigExport = false
    @State private var choosingInstall: PendingAdd?
    @State private var showDeviceManagement = false
    @State private var showSystem: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_SYSTEM"] != nil
        #else
        return false
        #endif
    }()
    @State private var serviceConfirm: ServicesSection.PendingAction?
    @State private var uninstallService: ServiceID?
    /// Presents the catalog picker for adding one more service
    @State private var addingService = false
    @State private var pendingUninstall: PendingUninstall?
    /// Which service's live log stream is open
    @State private var logsService: ServiceID?
    /// Which VPN protocol the VPN segment shows
    @State private var vpnProtocol: ServiceID?
    /// Which segment of the dashboard is shown
    @State private var addingPanel = false
    @State private var editingPanel: MetricPanel?
    /// Where a tapped panel goes
    @State private var panelHistory: MetricsHistoryTarget?
    /// The Security screen a tapped row opens
    @State private var securityRoute: SecurityRoute?
    @State private var arrangingPanels = false

    @AppStorage(MetricsDisplaySettings.placementKey)
    private var metricsPlacementRaw = MetricsPlacement.both.rawValue
    private var showsMetricsTab: Bool {
        MetricsDisplaySettings.placement(from: metricsPlacementRaw).showsInsideServer
    }

    @AppStorage(VPNDisplaySettings.placementKey)
    private var vpnPlacementRaw = VPNPlacement.both.rawValue
    private var showsVPNTab: Bool {
        guard VPNDisplaySettings.placement(from: vpnPlacementRaw).showsInsideServer else { return false }
        return viewModel.hasVPNProtocol
    }

    private var visibleTabs: [DashboardTab] {
        segments.ordered(availableTabs, on: viewModel.deployment.id)
    }

    private var availableTabs: [DashboardTab] {
        DashboardTab.visible(showingMetrics: showsMetricsTab,
                             showingContainers: showsContainersInside,
                             showingVPN: showsVPNTab,
                             showingTerminal: true)
    }

    @ObservedObject private var segments = DashboardTabSettings.shared
    @ObservedObject private var barSettings = TabBarSettings.shared
    @ObservedObject private var tunnel = TunnelController.shared
    @State private var arrangingSegments = false

    @AppStorage(ContainersDisplaySettings.placementKey)
    private var containersPlacementRaw = ContainersPlacement.server.rawValue
    /// Whether this server's own screen carries the containers block
    private var showsContainersInside: Bool {
        guard viewModel.canListContainers else { return false }
        return ContainersDisplaySettings.placement(from: containersPlacementRaw).showsInsideServer
    }

    @AppStorage(TerminalDisplaySettings.placementKey)
    private var terminalPlacementRaw = TerminalPlacement.server.rawValue
    /// A row rather than a segment of its own
    private var showsTerminalInside: Bool {
        TerminalDisplaySettings.placement(from: terminalPlacementRaw).showsInsideServer
    }

    @ObservedObject private var navigator = AppNavigator.shared
    @ObservedObject private var tour = AppTour.shared

    @State private var tab: DashboardTab = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_DASHBOARD_TAB"],
           let requested = DashboardTab(rawValue: raw) {
            return requested
        }
        #endif
        return DashboardTabSettings.shared.startTab
    }()

    init(deployment: Deployment, onUpdate: @escaping (Deployment) -> Void,
         onDelete: ((Deployment) -> Void)? = nil) {
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        let model = DashboardViewModel(deployment: deployment)
        model.onDeploymentCorrected = onUpdate
        _viewModel = StateObject(wrappedValue: model)
    }

    var body: some View {
        panelSheets(maintenanceSheets(serviceSheets(backupSheets(connectionSheets(chrome)))))
            .dismissHandle(dismiss)
    }

    private var chrome: some View {
        content
            .navigationTitle(viewModel.deployment.name)
            .raisedNavigationTitle()
            .toolbar { toolbarItems }
            #if os(iOS)
            .toolbarBackground(Self.headerPlate, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .sheet(isPresented: $arrangingSegments) {
                DashboardTabOrderView(available: availableTabs,
                                      deploymentID: viewModel.deployment.id)
            }
            .task(id: viewModel.deployment.id) { await storage.load(viewModel.deployment) }
            #if DEBUG
            .task {
                if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_ARRANGE_SEGMENTS"] != nil {
                    arrangingSegments = true
                }
            }
            .task {
                guard let raw = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_SWITCH_SECTION"]
                else { return }
                for target in raw.split(separator: ",").compactMap({ DashboardTab(rawValue: String($0)) }) {
                    try? await Task.sleep(for: .milliseconds(1500))
                    #if os(iOS)
                    FrameProbe.note("section \(target.rawValue)")
                    #endif
                    tab = target
                }
            }
            .task {
                guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_SERVER_SETTINGS"] != nil
                else { return }
                try? await Task.sleep(for: .milliseconds(1200))
                showSettings = true
            }
            .task {
                guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_ADD_SERVICE"] != nil else { return }
                try? await Task.sleep(for: .milliseconds(1200))
                addingService = true
            }
            .task {
                guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_INSTALL_METHOD"] != nil,
                      let service = ServiceRegistry.service(.shadowsocks) else { return }
                try? await Task.sleep(for: .milliseconds(1200))
                choosingInstall = PendingAdd(services: [service],
                                             scripts: AddedServiceScripts.scripts(for: [service],
                                                                                  on: viewModel.deployment))
            }
            #endif
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .principal) {
            tabPicker.labelsHidden()
        }
        #endif
        ToolbarItemGroup(placement: .primaryAction) {
            RunningProcessButton()
            Menu {
                Button {
                    showSettings = true
                } label: {
                    Label("Connection Settings", systemImage: "gearshape")
                }
                Button {
                    showKeySheet = true
                } label: {
                    Label("App SSH Key", systemImage: "key.horizontal")
                }
                Button {
                    arrangingSegments = true
                } label: {
                    Label("Sections", systemImage: "arrow.up.arrow.down")
                }
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .toolbarGlassButtonStyle()
        }
    }

    private func connectionSheets(_ base: some View) -> some View {
        base
            .sheet(isPresented: $showSettings) {
                ServerFormView(mode: .edit(viewModel.deployment),
                               onSave: { updated in
                    onUpdate(updated)
                    viewModel.invalidateSession()
                })
            }
            .sheet(isPresented: $showKeySheet) {
                DeploymentKeyView(deploymentID: viewModel.deployment.id) {
                    viewModel.invalidateSession()
                }
            }
    }

    private func backupSheets(_ base: some View) -> some View {
        base
            .sheet(item: backupSheetBinding, onDismiss: {
                guard let pending = pendingBackup else { return }
                pendingBackup = nil
                guard let managed = ServiceRegistry.service(pending.serviceID) else { return }
                Task {
                    await viewModel.runWrapperBackup(managed, encrypt: pending.encrypt,
                                                     passphrase: pending.passphrase)
                }
            }) { target in
                if let service = ServiceRegistry.service(target.id) {
                    BackupConfirmSheet(
                        serviceName: service.displayName,
                        encryptsByDefault: service.actions(viewModel.deployment.serviceContext)
                            .backup?.encryptsByDefault ?? false,
                        loadEstimate: { try await viewModel.estimateBackup(service) },
                        onCancel: { backupService = nil },
                        onConfirm: { encrypt, passphrase in
                            pendingBackup = PendingBackup(serviceID: target.id, encrypt: encrypt,
                                                          passphrase: passphrase)
                            backupService = nil
                        }
                    )
                }
            }
            .sheet(item: passphraseSheetBinding, onDismiss: {
                guard let pending = pendingEncryptedBackup else { return }
                pendingEncryptedBackup = nil
                if let managed = ServiceRegistry.service(pending.serviceID) {
                    Task { await viewModel.runEncryptedBackup(managed, passphrase: pending.passphrase) }
                }
            }) { service in
                PassphraseSheet(
                    onCancel: { passphraseService = nil },
                    onConfirm: { passphrase in
                        pendingEncryptedBackup = PendingEncryptedBackup(serviceID: service.id,
                                                                        passphrase: passphrase)
                        passphraseService = nil
                    }
                )
            }
            .sheet(item: restoreSheetBinding, onDismiss: {
                guard let pending = pendingRestore else { return }
                pendingRestore = nil
                confirmingRestore = pending
            }) { target in
                if let service = ServiceRegistry.service(target.id) {
                    RestoreSheet(
                        service: service,
                        needsPassphrase: service.actions(viewModel.deployment.serviceContext)
                            .restore?.needsPassphrase ?? false,
                        loadBackups: { try await viewModel.restorableBackups(service) },
                        onCancel: { restoreService = nil },
                        onChoose: { source, passphrase in
                            pendingRestore = PendingRestore(serviceID: target.id, source: source,
                                                            passphrase: passphrase)
                            restoreService = nil
                        }
                    )
                }
            }
    }

    private func addServiceSheets(_ base: some View) -> some View {
        base
            .sheet(isPresented: $addingService) {
                AddServiceSheet(
                    installed: viewModel.deployment.services,
                    localOnly: viewModel.deployment.scope == .localOnly,
                    installsAgentFirst: !viewModel.deployment.usesAgent,
                    loadArrays: { await viewModel.dataArrays() },
                    memoryBytes: viewModel.hostMetrics[viewModel.deployment.servicesHost]?.value?.memTotalBytes,
                    onCancel: { addingService = false },
                    onInstall: { services, mount in
                        addingService = false
                        if let mount { onUpdate(viewModel.placeData(of: services, under: mount)) }
                        let pending = PendingAdd(services: services,
                                                 scripts: AddedServiceScripts.scripts(for: services,
                                                                                      on: viewModel.deployment))
                        // One sheet closes before the next opens.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { choosingInstall = pending }
                    }
                )
            }
            .sheet(item: $rerunning) { pending in
                InstallMethodSheet(
                    services: pending.services,
                    scripts: pending.scripts,
                    purpose: pending.purpose,
                    onDevice: {
                        rerunning = nil
                        Task {
                            if let updated = await viewModel.rerunServices(repair: pending.purpose == .repair) {
                                onUpdate(updated)
                            }
                        }
                    },
                    onCancel: { rerunning = nil })
            }
            .sheet(item: $choosingInstall) { pending in
                InstallMethodSheet(
                    services: pending.services,
                    scripts: pending.scripts,
                    onDevice: {
                        choosingInstall = nil
                        Task {
                            if let updated = await viewModel.addServices(pending.services) { onUpdate(updated) }
                        }
                    },
                    onCancel: { choosingInstall = nil })
            }
    }

    private func serviceSheets(_ base: some View) -> some View {
        addServiceSheets(base)
            .sheet(item: uninstallSheetBinding, onDismiss: {
                guard let pending = pendingUninstall else { return }
                pendingUninstall = nil
                guard let service = ServiceRegistry.service(pending.serviceID) else { return }
                Task {
                    if let updated = await viewModel.uninstall(service, purge: pending.purge) {
                        onUpdate(updated)
                    }
                }
            }) { target in
                if let service = ServiceRegistry.service(target.id) {
                    UninstallServiceSheet(
                        service: service,
                        alsoRemoved: Self.alsoRemovedNames(with: service, installed: viewModel.deployment.services),
                        unguardedPanels: unguardedPanelNames(removing: service),
                        onCancel: { uninstallService = nil },
                        onConfirm: { purge in
                            pendingUninstall = PendingUninstall(serviceID: target.id, purge: purge)
                            uninstallService = nil
                        }
                    )
                }
            }
            .sheet(item: logsSheetBinding) { target in
                if let service = ServiceRegistry.service(target.id) {
                    ServiceLogsSheet(deployment: viewModel.deployment,
                                     service: service,
                                     source: logsSource(for: service))
                }
            }
            .alert("Restore and replace the current data?",
                   isPresented: Binding(get: { confirmingRestore != nil },
                                                     set: { if !$0 { confirmingRestore = nil } }),
                                presenting: confirmingRestore) { pending in
                Button("Restore", role: .destructive) {
                    confirmingRestore = nil
                    guard let service = ServiceRegistry.service(pending.serviceID) else { return }
                    Task {
                        await viewModel.runRestore(service, from: pending.source,
                                                   passphrase: pending.passphrase)
                    }
                }
                .dangerTint()
                Button("Cancel", role: .cancel) { confirmingRestore = nil }
            } message: { _ in
                Text("Everything the service holds now is replaced by the backup. This cannot be undone.")
            }
    }

    private func maintenanceSheets(_ base: some View) -> some View {
        base
            .onChange(of: viewModel.erased) { _, erased in
                guard erased else { return }
                let deployment = viewModel.deployment
                dismiss()
                DispatchQueue.main.async { onDelete?(deployment) }
            }
            .alert("Repair this server?", isPresented: $confirmingRepair) {
                Button("Repair") { startReinstall(editFirst: false) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Re-runs the setup with this server's saved configuration — the firewall, web sites, permissions and any stopped container are put back. Services and their data are kept.")
            }
            .sheet(isPresented: $showErase, onDismiss: {
                guard let purge = pendingErasePurge else { return }
                pendingErasePurge = nil
                Task { await viewModel.fullCleanup(purge: purge) }
            }) {
                EraseServerSheet(
                    deployment: viewModel.deployment,
                    onCancel: { showErase = false },
                    onConfirm: { purge in
                        pendingErasePurge = purge
                        showErase = false
                    })
            }
            .alert(quickActionTitle,
                   isPresented: Binding(get: { viewModel.quickActionResult != nil },
                                        set: { if !$0 { viewModel.quickActionResult = nil } }),
                   presenting: viewModel.quickActionResult) { _ in
                Button("OK") { viewModel.quickActionResult = nil }
            } message: { result in
                Text(result.message)
            }
    }

    private func panelSheets(_ base: some View) -> some View {
        base
            .sheet(isPresented: $showAccessAndPasswords) {
                NavigationStack {
                    InstallReportView(deployment: viewModel.deployment)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showAccessAndPasswords = false }
                            }
                        }
                }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 520)
                #endif
            }
            .sheet(isPresented: $showConfigExport) {
                NavigationStack {
                    ServerConfigExportView(viewModel: viewModel)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showConfigExport = false }
                            }
                        }
                }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 520)
                #endif
            }
            .sheet(isPresented: $showSystem) {
                NavigationStack {
                    SystemUpdatePage(viewModel: viewModel)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showSystem = false }
                            }
                        }
                }
                #if os(macOS)
                .frame(minWidth: 480, minHeight: 520)
                #endif
            }
            .sheet(isPresented: $showDeviceManagement) {
                if #available(macOS 15.0, *) {
                    DeviceManagementSheet(deployment: viewModel.deployment)
                }
            }
            .sheet(isPresented: $showAgent) { agentPage }
            .onReceive(NotificationCenter.default.publisher(for: .gryonixDeploymentInstalled)) { note in
                guard note.object as? UUID == viewModel.deployment.id else { return }
                viewModel.invalidateSession()
                Task {
                    if let updated = await viewModel.checkAgent() { onUpdate(updated) }
                    await viewModel.refreshAll()
                }
            }
    }

    private var quickActionTitle: Text {
        viewModel.quickActionResult?.isError == true ? Text("Error") : Text("Done")
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        dashboardList
        #else
        dashboardList
            .contentMargins(.top, 12, for: .scrollContent)
            .safeAreaInset(edge: .top, spacing: 0) {
                sectionStrip
                    .appTourTarget(.serverStrip)
                    .onHeaderPlate()
            }
        #endif
    }

    #if os(iOS)

    /// The system strip cannot scroll, so long titles use ours
    @ViewBuilder
    private var sectionStrip: some View {
        if barSettings.sectionStripStyle == .custom {
            customStrip
        } else if barSettings.sectionLabels == .icons {
            systemStrip(showsTitles: false)
        } else {
            ViewThatFits(in: .horizontal) {
                titleWidthProbe
                    .frame(maxWidth: .infinity)
                    .overlay { systemStrip(showsTitles: true) }
                customStrip
            }
        }
    }

    /// Hidden titles that give the system strip a real width
    private var titleWidthProbe: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                Text(tab.title)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
            }
        }
        .fixedSize()
        .padding(.horizontal, 16)
        .frame(height: stripHeight + 16)
        .hidden()
    }

    private var customStrip: some View {
        DashboardSegmentStrip(tabs: visibleTabs, labels: barSettings.sectionLabels,
                              tunnelActive: tunnel.status.isActive,
                              selection: $tab) { held in
            segmentMenu(for: held)
        }
        .padding(.horizontal, 16)
        // Room above for the lens that lifts while held.
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func systemStrip(showsTitles: Bool) -> some View {
        systemTabPicker(showsTitles: showsTitles)
            .frame(height: stripHeight)
            .segmentMenus(count: visibleTabs.count, probe: "sections") { index in
                guard visibleTabs.indices.contains(index) else { return nil }
                return segmentMenu(for: visibleTabs[index])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }

    private func systemTabPicker(showsTitles: Bool) -> some View {
        Picker("View", selection: $tab) {
            ForEach(visibleTabs) { tab in
                if showsTitles {
                    Text(tab.title).tag(tab)
                } else {
                    tab.icon(tunnelActive: tunnel.status.isActive)
                        .accessibilityLabel(Text(tab.title))
                        .tag(tab)
                }
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
    }
    #endif

    #if os(macOS)
    private var tabPicker: some View {
        Picker("View", selection: $tab) {
            ForEach(visibleTabs) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }
    #endif

    #if os(iOS)
    private func segmentMenu(for held: DashboardTab) -> UIMenu {
        var children: [UIMenuElement] = []
        let id = viewModel.deployment.id
        var second: [UIMenuElement] = []
        if segments.canHide(held, on: id, available: availableTabs) {
            second.append(UIAction(title: UIL10n.string("Hide this section"),
                                   image: UIImage(systemName: "eye.slash"),
                                   attributes: .destructive) { _ in
                DashboardTabSettings.shared.setVisible(false, for: held, on: id,
                                                       available: availableTabs)
            })
        }
        second.append(UIAction(title: UIL10n.string("Sections"),
                               image: UIImage(systemName: "arrow.up.arrow.down")) { _ in
            arrangingSegments = true
        })
        children.append(UIMenu(title: "", options: .displayInline, children: second))
        return UIMenu(title: UIL10n.string(held.titleKey), children: children)
    }

    #endif

    private func requestAccessAndPasswords() async {
        guard gateAccessScreen else {
            showAccessAndPasswords = true
            return
        }
        let reason = UIL10n.string("Unlock to view logins & passwords")
        if await BiometricGate.authenticate(reason: reason) {
            showAccessAndPasswords = true
        }
    }

    /// Identifiable wrapper for sheet(item:) over ServiceID
    private struct ServiceSheetTarget: Identifiable {
        let id: ServiceID
    }

    /// Captured on Confirm, consumed in the sheet's onDismiss
    private struct PendingEncryptedBackup {
        let serviceID: ServiceID
        let passphrase: String
    }

    private var passphraseSheetBinding: Binding<ServiceSheetTarget?> {
        Binding(
            get: { passphraseService.map(ServiceSheetTarget.init) },
            set: { passphraseService = $0?.id }
        )
    }

    private struct PendingBackup {
        let serviceID: ServiceID
        let encrypt: Bool
        let passphrase: String?
    }

    private var backupSheetBinding: Binding<ServiceSheetTarget?> {
        Binding(
            get: { backupService.map(ServiceSheetTarget.init) },
            set: { backupService = $0?.id }
        )
    }

    private struct PendingRestore {
        let serviceID: ServiceID
        let source: DashboardViewModel.RestoreSource
        let passphrase: String?
    }

    /// A confirmed service removal, waiting for its sheet to close
    private struct PendingUninstall {
        let serviceID: ServiceID
        let purge: PurgeOptions
    }

    /// Services picked to add, before choosing how
    struct PendingAdd: Identifiable {
        let id = UUID()
        let services: [any ManagedService]
        let scripts: [Artifact]
    }

    private func unguardedPanelNames(removing service: any ManagedService) -> [String] {
        let removed = DashboardViewModel.removedServices(with: service, installed: viewModel.deployment.services)
        guard removed.contains(.vpnPanel), let state = viewModel.adminLockdown.value,
              state.isActive else { return [] }
        return viewModel.lockdownPages
            .filter { !removed.contains($0.id) && state.guards($0.host) }
            .map(\.name)
    }

    private static func alsoRemovedNames(with service: any ManagedService,
                                         installed: Set<ServiceID>) -> [String] {
        let removed = DashboardViewModel.removedServices(with: service, installed: installed)
        guard removed.count > 1 else { return [] }
        return ServiceRegistry.services(removed.subtracting([service.id]))
            .map(\.displayName)
    }

    private var restoreSheetBinding: Binding<ServiceSheetTarget?> {
        Binding(
            get: { restoreService.map(ServiceSheetTarget.init) },
            set: { restoreService = $0?.id }
        )
    }

    private func copyToClipboard(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    private var uninstallSheetBinding: Binding<ServiceSheetTarget?> {
        Binding(
            get: { uninstallService.map(ServiceSheetTarget.init) },
            set: { uninstallService = $0?.id }
        )
    }

    /// Which route the sheet reads on
    private func logsSource(for service: any ManagedService) -> ServiceLogsSheet.Source {
        if #available(macOS 15.0, *),
           viewModel.deployment.usesAgent,
           let agentID = AgentServiceMapping.agentID(for: service.id) {
            return .agent(serviceID: agentID, host: viewModel.agentHost(for: service.id))
        }
        return .snapshot { @Sendable in try await viewModel.serviceLogs(service) }
    }

    private var logsSheetBinding: Binding<ServiceSheetTarget?> {
        Binding(
            get: { logsService.map(ServiceSheetTarget.init) },
            set: { logsService = $0?.id }
        )
    }

    private var dashboardList: some View {
        ScrollViewReader { scroll in
            cardAlerts(cardList)
                #if os(iOS)
                .background {
                    SectionSwipe(canMove: { width in
                        target(of: width < 0 ? 1 : -1, from: tab, among: visibleTabs) != nil
                    }) { width in
                        move(by: width < 0 ? 1 : -1, showing: $tab, among: visibleTabs)
                    }
                }
                #endif
                .onChange(of: tour.step, initial: true) { _, step in follow(step, scroll: scroll) }
                #if DEBUG
                .task { await scrollForScreenshot(scroll) }
                #endif
        }
    }

    #if DEBUG
    private func scrollForScreenshot(_ scroll: ScrollViewProxy) async {
        guard let target = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_SCROLL_TO"] else { return }
        for delay in [900, 2_600] {
            try? await Task.sleep(for: .milliseconds(delay))
            withAnimation { scroll.scrollTo(target, anchor: .top) }
        }
    }
    #endif

    /// Shows the page and part a tour step talks about
    private func follow(_ step: AppTourStep?, scroll: ScrollViewProxy) {
        guard let step, case .server(let page) = step.place, visibleTabs.contains(page) else { return }
        tab = page
        if step == .security {
            tour.hold(step)
            Task { await revealSecurity(scroll) }
        } else if page == .general {
            Task { await scrollToTop(during: step) }
        }
    }

    private func scrollToTop(during step: AppTourStep) async {
        #if os(iOS)
        for delay in [350, 500, 700] {
            try? await Task.sleep(for: .milliseconds(delay))
            guard tour.step == step else { return }
            VisibleListScroller.scrollToTop()
        }
        #endif
    }

    /// Scrolls Protection in once, then lets the tour frame it
    private func revealSecurity(_ scroll: ScrollViewProxy) async {
        defer { tour.arrive(.security) }
        try? await Task.sleep(for: .milliseconds(350))
        guard tour.step == .security else { return }
        withAnimation(.easeInOut(duration: 0.5)) { scroll.scrollTo("security", anchor: .top) }
        try? await Task.sleep(for: .milliseconds(600))
        #if os(iOS)
        guard tour.step == .security, let strip = tour.frames[.serverStrip],
              let security = tour.frames[.serverSecurity] else { return }
        let offset = security.minY - (strip.maxY + 56)
        guard abs(offset) > 8 else { return }
        VisibleListScroller.scroll(by: offset)
        try? await Task.sleep(for: .milliseconds(350))
        #endif
    }

    #if os(iOS)
    /// Through a binding, which stays live in a kept closure
    private func move(by step: Int, showing tab: Binding<DashboardTab>,
                      among sections: [DashboardTab]) {
        guard let next = target(of: step, from: tab.wrappedValue, among: sections) else { return }
        Haptics.play(.tap)
        tab.wrappedValue = next
    }

    private func target(of step: Int, from tab: DashboardTab,
                        among sections: [DashboardTab]) -> DashboardTab? {
        guard let showing = sections.firstIndex(of: tab) else { return nil }
        let next = showing + step
        return sections.indices.contains(next) ? sections[next] : nil
    }
    #endif

    private var cardList: some View {
        SlidingPages(pages: visibleTabs, selection: tab) { section in
            sectionPage(section)
        }
        #if DEBUG
        .modifier(DemoStartAtBottom())
        #endif
        .onChange(of: visibleTabs, initial: true) { _, visible in
            if !visible.contains(tab) { tab = visible.first ?? .general }
        }
        .navigationDestination(item: $panelHistory) { target in
            MetricsHistoryView(deployment: target.deployment, host: target.host,
                               initialMetric: target.metric)
        }
        .navigationDestination(item: $securityRoute) { route in
            securityScreen(route)
        }
        .sheet(isPresented: $addingPanel) {
            MetricPanelEditor(deployments: [viewModel.deployment], panel: nil) {
                MetricPanelStore.shared.add($0)
            }
        }
        .sheet(item: $editingPanel) { panel in
            MetricPanelEditor(deployments: [viewModel.deployment], panel: panel) {
                MetricPanelStore.shared.replace($0)
            }
        }
        .sheet(isPresented: $arrangingPanels) {
            MetricPanelReorderView(deploymentID: viewModel.deployment.id,
                                   deployments: [viewModel.deployment])
        }
        .refreshableWithShortcut { await viewModel.refreshAll() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.resumeInstalls() }
        }
        .task {
            await viewModel.refreshAll()
            if let updated = await viewModel.refreshWakeOnLANQuietly() { onUpdate(updated) }
            await viewModel.loadAgentVersion()
            if #available(macOS 15.0, *) { await viewModel.syncNotifyPreferences() }
            await viewModel.loadSelfUpdateStatus()
            await viewModel.resumeInstalls()
        }
    }

    private func sectionPage(_ section: DashboardTab) -> some View {
        CardList {
            if let error = viewModel.connectionError {
                Section {
                    Label(error, systemImage: HealthLevel.critical.systemImageName)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            switch section {
            case .general: generalTab
            case .operations: operationsTab
            case .hosts: if showsMetricsTab { hostsTab }
            case .containers:
                if showsContainersInside, #available(macOS 15.0, *) {
                    ServerContainersSection(deployment: viewModel.deployment)
                }
            case .vpn: if showsVPNTab { vpnTab }
            case .terminal:
                if showsTerminalInside, #available(macOS 15.0, *) {
                    ServerTerminalSection(deployment: viewModel.deployment)
                }
                FilesSection(deployment: viewModel.deployment)
            }
        }
    }

    private func cardAlerts(_ base: some View) -> some View {
        base
            .alert(serviceConfirm?.title ?? "",
                   isPresented: Binding(get: { serviceConfirm != nil },
                                                     set: { if !$0 { serviceConfirm = nil } }),
                                presenting: serviceConfirm) { action in
                Button("Continue", role: .destructive) {
                    serviceConfirm = nil
                    guard let service = viewModel.services.first(where: { $0.id == action.serviceID }) else { return }
                    Task {
                        switch action.kind {
                        case .restart: await viewModel.restart(service)
                        case .stop: await viewModel.stop(service)
                        case .update: await viewModel.update(service)
                        }
                    }
                }
                .dangerTint()
                Button("Cancel", role: .cancel) { serviceConfirm = nil }
            } message: { action in
                Text(action.message)
            }
            .alert("Administrator password",
                   isPresented: Binding(get: { viewModel.sudoPrompt != nil },
                                        set: { if !$0 { viewModel.answerSudoPrompt(nil) } }),
                   presenting: viewModel.sudoPrompt) { _ in
                SecureField("Account password", text: $sudoPassword)
                Button("Allow") {
                    viewModel.answerSudoPrompt(sudoPassword)
                    sudoPassword = ""
                }
                Button("Cancel", role: .cancel) {
                    viewModel.answerSudoPrompt(nil)
                    sudoPassword = ""
                }
            } message: { prompt in
                Text(verbatim: [UIL10n.string(
                    "%@ needs administrator rights. Enter its password once: the app sets up access by itself and does not keep the password.",
                    prompt.username), prompt.note].compactMap { $0 }.joined(separator: "\n\n"))
            }
            .alert("A newer agent is available",
                   isPresented: Binding(get: { viewModel.agentUpdateOffer != nil },
                                        set: { if !$0 { viewModel.agentUpdateOffer = nil } }),
                   presenting: viewModel.agentUpdateOffer) { _ in
                Button("Update") {
                    viewModel.agentUpdateOffer = nil
                    Task {
                        if let updated = await viewModel.installAgent() { onUpdate(updated) }
                    }
                }
                Button("Later", role: .cancel) { viewModel.agentUpdateOffer = nil }
            } message: { installed in
                Text(verbatim: UIL10n.string(
                    "This server runs %1$@; the app carries %2$@. Updating rebuilds it on the server and takes a few minutes.",
                    installed, viewModel.bundledAgentVersion))
            }
    }

    // MARK: - Tabs

    /// The screen one Security row pushes
    @ViewBuilder
    private func securityScreen(_ route: SecurityRoute) -> some View {
        switch route {
        case .adminPanels: AdminPanelsView(viewModel: viewModel)
        case .crowdSec: CrowdSecSettingsView(viewModel: viewModel)
        case .sshAccess: SSHAccessView(viewModel: viewModel)
        }
    }

    private func disclosureRow(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var generalTab: some View {
        SitesSection(viewModel: viewModel)
        if viewModel.isRelay {
            GeneralStatusSection(viewModel: viewModel)
        }
        Section {
            Button {
                Task { await requestAccessAndPasswords() }
            } label: {
                disclosureRow("Login & Passwords", systemImage: "key.horizontal")
            }
            .buttonStyle(.plain)
            Button {
                showConfigExport = true
            } label: {
                disclosureRow("Configuration (DNS, DKIM, ports)", systemImage: "doc.text.magnifyingglass")
            }
            .buttonStyle(.plain)
            if viewModel.canManageDevices {
                Button {
                    showDeviceManagement = true
                } label: {
                    disclosureRow("Paired Devices", systemImage: "list.bullet.rectangle.portrait")
                }
                .buttonStyle(.plain)
            }
            Button {
                showSystem = true
            } label: {
                disclosureRow("Server system", systemImage: "shippingbox")
            }
            .buttonStyle(.plain)
        }
        .id("access")
        StorageSection(deployment: viewModel.deployment, overview: storage)
        if viewModel.canShowSecurity {
            SecuritySection(viewModel: viewModel, route: $securityRoute)
                .id("security")
        }
        Section {
            Button {
                showAgent = true
            } label: {
                disclosureRow("Agent", systemImage: "cpu")
            }
            .buttonStyle(.plain)
        }
        hostActionsSection
        eraseSection
    }

    /// The agent's own page, opened from its row
    private var agentPage: some View {
        NavigationStack {
            Form {
                AgentSection(version: viewModel.agentVersion,
                             usesAgent: viewModel.deployment.usesAgent,
                             command: viewModel.agentInstallCommand,
                             onCopy: {
                                 copyToClipboard(viewModel.agentInstallCommand)
                                 viewModel.quickActionResult = QuickActionResult(
                                     message: UIL10n.string("The command is on the clipboard. Run it from the project folder."),
                                     isError: false)
                             },
                             onInstall: {
                                 Task {
                                     if let updated = await viewModel.installAgent() { onUpdate(updated) }
                                 }
                             },
                             onCheck: {
                                 Task {
                                     if let updated = await viewModel.checkAgent() { onUpdate(updated) }
                                 }
                             },
                             isChecking: viewModel.isCheckingAgent,
                             checkResult: viewModel.agentCheck.map { result in
                                 switch result {
                                 case .installed(let version): return .installed(version: version)
                                 case .installedUnknownVersion: return .installedUnknownVersion
                                 case .unreachable(let reason): return .unreachable(reason)
                                 }
                             },
                             showsRelay: viewModel.canProvisionRelay,
                             onConfigureRelay: { Task { await viewModel.provisionRelay() } },
                             showsDynamicDNS: viewModel.canManageDynamicDNS,
                             dynamicDNSIsOn: viewModel.dynamicDNS?.enabled ?? false,
                             onDynamicDNS: { showingDynamicDNS = true },
                             showsNotifications: viewModel.canManageNotifications,
                             onNotifications: { showingNotifications = true },
                             onRemove: {
                                 Task { if let updated = await viewModel.removeAgent() { onUpdate(updated) } }
                             },
                             onReinstall: {
                                 Task { if let updated = await viewModel.installAgent(reinstall: true) { onUpdate(updated) } }
                             },
                             nodesDestination: AnyView(DeploymentNodesView(deployment: viewModel.deployment,
                                                                          onUpdate: onUpdate)))
                AgentOpeningCheckRow(deploymentID: viewModel.deployment.id)
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Agent"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showAgent = false }
                }
            }
            .sheet(isPresented: $showingDynamicDNS) {
                if #available(macOS 15.0, *) {
                    DynamicDNSSheet(viewModel: viewModel)
                }
            }
            .sheet(isPresented: $showingNotifications) {
                if #available(macOS 15.0, *) {
                    NotificationsSheet(viewModel: viewModel)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    @ViewBuilder private var hostActionsSection: some View {
        if viewModel.isRelay {
            HostControlSection(viewModel: viewModel,
                               onRepair: { askRerun(.repair) },
                               onReinstall: { askRerun(.reinstall) },
                               onUpdate: onUpdate)
        } else {
            SingleHostActionsSection(viewModel: viewModel,
                                     onRepair: { askRerun(.repair) },
                                     onReinstall: { askRerun(.reinstall) },
                                     onUpdate: onUpdate)
        }
    }

    @ViewBuilder private var operationsTab: some View {
        ServicesSection(viewModel: viewModel, requestPassphrase: { serviceID in
            passphraseService = serviceID
        }, requestBackup: { serviceID in
            backupService = serviceID
        }, requestRestore: { serviceID in
            restoreService = serviceID
        }, requestConfirm: { action in
            serviceConfirm = action
        }, requestUninstall: { serviceID in
            uninstallService = serviceID
        }, requestLogs: { serviceID in
            logsService = serviceID
        }, requestVPNDevices: { serviceID in
            vpnProtocol = serviceID
            tab = .vpn
        }, onUpdate: onUpdate)
        addServiceSection
        if viewModel.hasBackupCapableService {
            AutoBackupSection(viewModel: viewModel, requests: BackupRequests(
                backup: { backupService = $0 },
                passphrase: { passphraseService = $0 },
                restore: { restoreService = $0 }))
                .id("autobackup")
        }
        AutoUpdateSection(viewModel: viewModel)
        AgentSelfUpdateSection(viewModel: viewModel)
    }

    /// The entry point for growing a server
    @ViewBuilder private var addServiceSection: some View {
        if viewModel.canAddServices {
            Section {
                Button {
                    addingService = true
                } label: {
                    Label("Add service", systemImage: "plus.circle")
                }
                .infoNote("Add service", "Installs another service from the catalog onto this server.")
            }
        }
    }

    /// Asks only how, as when adding a service
    private func askRerun(_ purpose: InstallMethodSheet.Purpose) {
        guard viewModel.deployment.usesAgent else {
            if purpose == .repair { confirmingRepair = true } else { startReinstall(editFirst: false) }
            return
        }
        let services = viewModel.deployment.installedServices
        rerunning = PendingRerun(purpose: purpose, services: services,
                                 scripts: AddedServiceScripts.scripts(for: services, on: viewModel.deployment))
    }

    /// Presents the reinstall flow
    private func startReinstall(editFirst: Bool) {
        let saved = ConfiguratorStore.shared.configForReinstall(deploymentID: viewModel.deployment.id)
        AppNavigator.shared.reinstallRequest = ReinstallRequest(
            deployment: viewModel.deployment,
            draft: ConfiguratorDraft(reinstalling: viewModel.deployment, saved: saved),
            editFirst: editFirst || saved == nil)
    }

    @ViewBuilder private var eraseSection: some View {
        Section {
            Button(role: .destructive) {
                showErase = true
            } label: {
                Label("Erase server", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .dangerTint()
        } footer: {
            Text("Removes everything gryonixNexus installed from this server's machine(s). You choose whether to also delete data and backups. To only take the server off this device, use Delete on its card instead.")
        }
    }

    @ViewBuilder private var hostsTab: some View {
        ForEach(viewModel.deployment.nodes) { node in
            let host = node.sshHost
            HostSection(title: hostSectionTitle(node),
                        storageKey: "\(viewModel.deployment.id)-\(host.persistedRaw)",
                        metrics: viewModel.hostMetrics[host] ?? .idle,
                        wireGuard: viewModel.showsWireGuard(node)
                            ? (viewModel.hostWireGuard[host] ?? .idle) : nil,
                        disk: viewModel.hostDisk[host] ?? .idle,
                        memory: viewModel.hostMemory[host] ?? .idle,
                        history: MetricsHistoryTarget(deployment: viewModel.deployment,
                                                      host: host),
                        tourTarget: .serverMetrics)
        }
        ServerPanelsSection(deployment: viewModel.deployment,
                            adding: $addingPanel, editing: $editingPanel,
                            history: $panelHistory, arranging: $arrangingPanels)
    }

    private func hostSectionTitle(_ node: DeploymentNode) -> LocalizedStringKey {
        if !node.name.isEmpty { return LocalizedStringKey(node.name) }
        switch node.legacySlot {
        case .vps: return viewModel.deployment.nodes.count > 1 ? "VPS" : "Server"
        case .home: return "Local server"
        case nil: return LocalizedStringKey(node.endpoint.host)
        }
    }

    private var vpnTab: some View {
        ServerVPNSection(viewModel: viewModel, selection: $vpnProtocol)
    }
}

#if os(iOS)
extension DashboardView {
    static let headerPlate = Color(.secondarySystemGroupedBackground)
}

private extension View {
    func onHeaderPlate() -> some View {
        background(DashboardView.headerPlate)
    }
}
#endif

/// The segments of a server's dashboard
enum DashboardTab: String, CaseIterable, Identifiable {
    case general, operations, hosts, containers, vpn, terminal

    var id: String { rawValue }

    /// The segments actually offered
    static func visible(showingMetrics: Bool, showingContainers: Bool = false,
                        showingVPN: Bool = false, showingTerminal: Bool = false) -> [DashboardTab] {
        allCases.filter { tab in
            switch tab {
            case .hosts: return showingMetrics
            case .containers: return showingContainers
            case .vpn: return showingVPN
            case .terminal: return showingTerminal
            default: return true
            }
        }
    }

    var title: LocalizedStringKey { LocalizedStringKey(titleKey) }

    /// The English source string, which is also the key
    var titleKey: String {
        switch self {
        case .general: return "General"
        case .operations: return "Apps"
        case .hosts: return "Metrics"
        case .containers: return "Containers"
        case .vpn: return "VPN"
        case .terminal: return "Terminal"
        }
    }

    /// What the strip prints
    var localizedTitle: String { UIL10n.string(titleKey) }

    var systemImage: String {
        switch self {
        case .general: return "square.grid.2x2"
        case .operations: return "slider.horizontal.3"
        case .hosts: return "chart.bar.xaxis"
        case .containers: return "shippingbox"
        case .vpn: return "lock.shield"
        case .terminal: return "apple.terminal"
        }
    }

    /// The bottom bar's VPN pictures; system symbols otherwise
    func iconName(tunnelActive: Bool) -> String {
        guard self == .vpn else { return systemImage }
        return tunnelActive ? "TabIconLogo" : "TabIconGlobe"
    }

    func icon(tunnelActive: Bool) -> Image {
        guard self == .vpn else { return Image(systemName: systemImage) }
        return Image(iconName(tunnelActive: tunnelActive))
    }
}

struct FilesSection: View {
    let deployment: Deployment

    var body: some View {
        Section("Files") {
            ForEach(deployment.nodes) { node in
                NavigationLink {
                    FileBrowserView(deployment: deployment, host: node.sshHost)
                } label: {
                    Label(rowTitle(node), systemImage: rowIcon(node))
                }
            }
        }
    }

    private func rowTitle(_ node: DeploymentNode) -> LocalizedStringKey {
        if !node.name.isEmpty { return LocalizedStringKey("\(node.name) files") }
        switch node.legacySlot {
        case .vps: return deployment.nodes.count > 1 ? "VPS files" : "Server files"
        case .home: return "Local server files"
        case nil: return LocalizedStringKey("\(node.endpoint.host) files")
        }
    }

    private func rowIcon(_ node: DeploymentNode) -> String {
        node.legacySlot == .home ? "folder.badge.person.crop" : "folder"
    }
}

struct SingleHostActionsSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onRepair: () -> Void
    let onReinstall: () -> Void
    let onUpdate: (Deployment) -> Void
    @State private var confirmingSSHRestart = false
    @State private var rebootTarget: SSHHostID?
    @State private var confirmingPowerOff = false

    var body: some View {
        Section("Actions") {
            // Two per row, same compact layout as the relay's HostControlSection.
            CompactActionGroup([
                CompactAction("Restart SSH", systemImage: "arrow.clockwise") {
                    confirmingSSHRestart = true
                }
            ]
            + viewModel.deployment.nodes.map { node in
                CompactAction(LocalizedStringKey(DashboardViewModel.rebootTitle(
                    for: node, in: viewModel.deployment)),
                              systemImage: "power", role: .destructive) {
                    rebootTarget = node.sshHost
                }
            }
            + (WakeOnLANAvailability.isOffered(for: viewModel.deployment)
               ? [CompactAction("Shut down", systemImage: "power.dotted", role: .destructive) {
                   confirmingPowerOff = true
               },
                  CompactAction("Wake on LAN", systemImage: "bolt") {
                      Task { if let updated = await viewModel.wakeUp() { onUpdate(updated) } }
                  }] : [])
            + [
                CompactAction("Repair server", systemImage: "wrench.and.screwdriver") {
                    onRepair()
                },
                CompactAction("Reinstall services", systemImage: "arrow.triangle.2.circlepath") {
                    onReinstall()
                }
            ])
            .listRowSeparator(.hidden)
            .padding(.vertical, 2)
            .alert(viewModel.sshdRestartQuestion,
                   isPresented: $confirmingSSHRestart) {
                Button("Restart", role: .destructive) {
                    Task { await viewModel.restartSSHDEverywhere() }
                }
                .dangerTint()
                Button("Cancel", role: .cancel) {}
            }
            .alert("Reboot this machine?",
                   isPresented: Binding(get: { rebootTarget != nil },
                                        set: { if !$0 { rebootTarget = nil } })) {
                Button("Reboot", role: .destructive) {
                    if let target = rebootTarget {
                        Task { await viewModel.rebootHost(target) }
                    }
                    rebootTarget = nil
                }
                .dangerTint()
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The machine will go offline for about a minute while it restarts.")
            }
            .alert("Shut down this machine?", isPresented: $confirmingPowerOff) {
                Button("Shut down", role: .destructive) {
                    Task { await viewModel.powerOffWakeTarget() }
                }
                .dangerTint()
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It stays off until Wake on LAN or its power button turns it on.")
            }
        }
    }
}

#if DEBUG
private struct DemoStartAtBottom: ViewModifier {
    private var wanted: Bool {
        ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_SCROLL"] != nil
    }

    func body(content: Content) -> some View {
        content.defaultScrollAnchor(wanted ? .bottom : .top)
    }
}
#endif

#Preview {
    NavigationStack {
        DashboardView(deployment: Deployment(
            name: "My server",
            topology: .vpsRelayWithHomeBackend,
            domain: "example.com",
            entry: HostEndpoint(host: "203.0.113.4", user: "admin"),
            homeWGAddress: "10.8.0.2",
            services: [.mailcow, .vaultwarden]
        )) { _ in }
    }
}

/// Repair or reinstall waiting for the user to say how
private struct PendingRerun: Identifiable {
    let id = UUID()
    let purpose: InstallMethodSheet.Purpose
    let services: [any ManagedService]
    let scripts: [Artifact]
}
