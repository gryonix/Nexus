import AgentControl
import ServerControl
import ServiceCatalog
import SwiftUI

struct ServicesSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    /// Prompts the user for the service's encrypted backup passphrase
    let requestPassphrase: (ServiceID) -> Void
    /// Opens the size estimate + options sheet for a wrapper-driven backup
    let requestBackup: (ServiceID) -> Void
    /// Opens the restore picker for this service
    let requestRestore: (ServiceID) -> Void
    /// Asks the parent to present the restart/update confirmation
    let requestConfirm: (PendingAction) -> Void
    /// Opens the removal confirmation for this service
    let requestUninstall: (ServiceID) -> Void
    let requestLogs: (ServiceID) -> Void
    let requestVPNDevices: (ServiceID) -> Void
    let onUpdate: (Deployment) -> Void
    @ObservedObject private var tabs = TabBarSettings.shared

    struct PendingAction: Identifiable {
        enum Kind { case restart, stop, update }
        let kind: Kind
        let serviceID: ServiceID
        let displayName: String
        var id: String { "\(kind)-\(serviceID.rawValue)" }

        var title: LocalizedStringKey {
            switch kind {
            case .restart: return "Restart \(displayName)?"
            case .stop: return "Stop \(displayName)?"
            case .update: return "Update \(displayName)?"
            }
        }

        var message: LocalizedStringKey {
            switch kind {
            case .restart: return "The service will be unavailable while it restarts."
            case .stop: return "The service stays offline until you start it again."
            case .update: return "A backup is taken first, and the service is rolled back if it does not come up. This may take up to 10 minutes — keep the app open."
            }
        }
    }

    var body: some View {
        if tabs.groupsServices(in: viewModel.services.map(\.id)) {
            ForEach(groupedServices, id: \.category) { group in
                ServiceCategoryRow(viewModel: viewModel,
                                   category: group.category,
                                   services: group.services,
                                   requestPassphrase: requestPassphrase,
                                   requestBackup: requestBackup,
                                   requestRestore: requestRestore,
                                   requestConfirm: requestConfirm,
                                   requestUninstall: requestUninstall,
                                   requestLogs: requestLogs,
                                   requestVPNDevices: requestVPNDevices,
                                   onUpdate: onUpdate)
            }
        } else {
            ForEach(viewModel.services, id: \.id) { service in
                ServiceRow(viewModel: viewModel,
                           service: service,
                           requestPassphrase: requestPassphrase,
                           requestBackup: requestBackup,
                           requestRestore: requestRestore,
                           requestConfirm: requestConfirm,
                           requestUninstall: requestUninstall,
                           requestLogs: requestLogs,
                           requestVPNDevices: requestVPNDevices,
                           onUpdate: onUpdate)
            }
        }
    }

    private var groupedServices: [(category: ServiceCategory, services: [any ManagedService])] {
        var order: [ServiceCategory] = []
        var buckets: [ServiceCategory: [any ManagedService]] = [:]
        for service in viewModel.services {
            let category = service.displayCategory
            if buckets[category] == nil {
                buckets[category] = []
                order.append(category)
            }
            buckets[category, default: []].append(service)
        }
        return order.sorted().map { ($0, buckets[$0] ?? []) }
    }
}

private struct ServiceCategoryRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    let category: ServiceCategory
    let services: [any ManagedService]
    let requestPassphrase: (ServiceID) -> Void
    let requestBackup: (ServiceID) -> Void
    let requestRestore: (ServiceID) -> Void
    let requestConfirm: (ServicesSection.PendingAction) -> Void
    let requestUninstall: (ServiceID) -> Void
    let requestLogs: (ServiceID) -> Void
    let requestVPNDevices: (ServiceID) -> Void
    let onUpdate: (Deployment) -> Void
    @AppStorage private var expanded: Bool

    init(viewModel: DashboardViewModel, category: ServiceCategory, services: [any ManagedService],
         requestPassphrase: @escaping (ServiceID) -> Void,
         requestBackup: @escaping (ServiceID) -> Void,
         requestRestore: @escaping (ServiceID) -> Void,
         requestConfirm: @escaping (ServicesSection.PendingAction) -> Void,
         requestUninstall: @escaping (ServiceID) -> Void,
         requestLogs: @escaping (ServiceID) -> Void,
         requestVPNDevices: @escaping (ServiceID) -> Void,
         onUpdate: @escaping (Deployment) -> Void) {
        self.viewModel = viewModel
        self.category = category
        self.services = services
        self.requestPassphrase = requestPassphrase
        self.requestBackup = requestBackup
        self.requestRestore = requestRestore
        self.requestConfirm = requestConfirm
        self.requestUninstall = requestUninstall
        self.requestLogs = requestLogs
        self.requestVPNDevices = requestVPNDevices
        self.onUpdate = onUpdate
        _expanded = AppStorage(wrappedValue: false,
                               "serviceCategoryExpanded.\(viewModel.deployment.id).\(category.id)")
    }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: Binding(
                get: { expanded },
                set: { newValue in withAnimation(.smooth) { expanded = newValue } }
            )) {
                ForEach(services, id: \.id) { service in
                    ServiceRow(viewModel: viewModel,
                               service: service,
                               requestPassphrase: requestPassphrase,
                               requestBackup: requestBackup,
                               requestRestore: requestRestore,
                               requestConfirm: requestConfirm,
                               requestUninstall: requestUninstall,
                               requestLogs: requestLogs,
                               requestVPNDevices: requestVPNDevices,
                               onUpdate: onUpdate)
                }
            } label: {
                HStack(spacing: 6) {
                    Label { Text(LocalizedStringKey(category.title)) } icon: { CategoryIcon(category: category) }
                    Text(verbatim: "\(services.count)")
                        .foregroundStyle(.secondary)
                }
                .appTourTarget(.serverApps)
            }
        }
    }
}

/// One service, folded away by default
private struct ServiceRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    let service: any ManagedService
    let requestPassphrase: (ServiceID) -> Void
    let requestBackup: (ServiceID) -> Void
    let requestRestore: (ServiceID) -> Void
    let requestConfirm: (ServicesSection.PendingAction) -> Void
    let requestUninstall: (ServiceID) -> Void
    let requestLogs: (ServiceID) -> Void
    let requestVPNDevices: (ServiceID) -> Void
    let onUpdate: (Deployment) -> Void
    @AppStorage private var expanded: Bool
    /// Whether the VPN devices row belongs here — see `VPNPlacement`
    @AppStorage(VPNDisplaySettings.placementKey)
    private var vpnPlacementRaw = VPNPlacement.both.rawValue
    #if DEBUG
    /// Set only by `GRYONIXNEXUS_DEMO_OPEN_MODELS` — the screenshot hook below
    @State private var openingModels = false
    #endif

    init(viewModel: DashboardViewModel, service: any ManagedService,
         requestPassphrase: @escaping (ServiceID) -> Void,
         requestBackup: @escaping (ServiceID) -> Void,
         requestRestore: @escaping (ServiceID) -> Void,
         requestConfirm: @escaping (ServicesSection.PendingAction) -> Void,
         requestUninstall: @escaping (ServiceID) -> Void,
         requestLogs: @escaping (ServiceID) -> Void,
         requestVPNDevices: @escaping (ServiceID) -> Void,
         onUpdate: @escaping (Deployment) -> Void) {
        self.viewModel = viewModel
        self.service = service
        self.requestPassphrase = requestPassphrase
        self.requestBackup = requestBackup
        self.requestRestore = requestRestore
        self.requestConfirm = requestConfirm
        self.requestUninstall = requestUninstall
        self.requestLogs = requestLogs
        self.requestVPNDevices = requestVPNDevices
        self.onUpdate = onUpdate
        _expanded = AppStorage(wrappedValue: false,
                               "serviceExpanded.\(viewModel.deployment.id).\(service.id.rawValue)")
    }

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: Binding(
                get: { expanded },
                set: { newValue in withAnimation(.smooth(duration: 0.32)) { expanded = newValue } }
            )) {
                content
            } label: {
                header.appTourTarget(.serverApps)
            }
        }
    }

    private var header: some View {
        HStack {
            Label(service.displayName, systemImage: service.systemImage)
                .font(.headline)
            Spacer()
            healthBadge
        }
    }

    @ViewBuilder
    private var healthBadge: some View {
        switch viewModel.serviceStatuses[service.id] ?? .idle {
        case .loaded(let containers):
            let unhealthy = containers.filter { $0.health != .ok }.count
            if containers.isEmpty {
                EmptyView()
            } else if unhealthy == 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Label {
                    Text(verbatim: "\(unhealthy)")
                } icon: {
                    Image(systemName: HealthLevel.warning.systemImageName)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            }
        case .loading:
            ProgressView().controlSize(.small)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var content: some View {
        let actions = service.actions(viewModel.deployment.serviceContext)
        CompactActionGroup(buttons(actions: actions))
            .listRowSeparator(.hidden)
            .padding(.vertical, 2)

        if service.id == .dockerMailserver {
            NavigationLink {
                MailboxesView(viewModel: viewModel)
            } label: {
                Label("Mailboxes", systemImage: "tray.full")
            }
        }

        if VPNClientProtocols.all.contains(service.id),
           VPNDisplaySettings.placement(from: vpnPlacementRaw).showsInsideServer,
           viewModel.vpnClientProtocols.contains(service.id) {
            Button {
                requestVPNDevices(service.id)
            } label: {
                Label("Devices", systemImage: "iphone.gen3")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        if service.id == .liteLLM, viewModel.deployment.usesAgent,
           #available(macOS 15.0, *) {
            NavigationLink {
                ModelKeysView(viewModel: viewModel)
            } label: {
                Label("API keys", systemImage: "key.horizontal")
            }
        }

        modelsLink

        if service.id == .minecraftJava, viewModel.deployment.usesAgent,
           #available(macOS 15.0, *) {
            NavigationLink {
                ModsView(viewModel: viewModel, onUpdate: onUpdate)
            } label: {
                Label(AgentModOperations.slot(forFlavour: viewModel.deployment.serviceSettings.minecraftJavaFlavour) == .plugins
                      ? "Plugins" : "Mods",
                      systemImage: "puzzlepiece.extension")
            }
        }

        if service.id == .vaultwarden, viewModel.deployment.usesAgent {
            VaultwardenSignupsRow(viewModel: viewModel, onUpdate: onUpdate)
            VaultwardenTwoFactorRow(deployment: viewModel.deployment)
        }

        if service.id == .headscale, viewModel.managesMesh {
            NavigationLink {
                MeshDevicesView(viewModel: viewModel)
            } label: {
                Label("Devices", systemImage: "laptopcomputer.and.iphone")
            }
        }

        statusRows

        if actions.backup != nil {
            ServiceBackupsView(
                service: service,
                state: viewModel.serviceBackups[service.id] ?? .idle,
                load: { await viewModel.loadBackups(service) },
                download: { try await viewModel.downloadBackup(service, at: $0) },
                pathFor: { viewModel.backupPath(service, entry: $0) },
                delete: { await viewModel.deleteBackup(service, entry: $0) },
                copies: viewModel.preRestoreCopies[service.id] ?? [],
                deleteCopy: { await viewModel.deletePreRestoreCopy(service, copy: $0) }
            )
        }
    }

    @ViewBuilder
    private var modelsLink: some View {
        if service.id == .ollama, viewModel.deployment.usesAgent,
           #available(macOS 15.0, *) {
            NavigationLink {
                ModelsView(viewModel: viewModel)
            } label: {
                Label("Models", systemImage: "shippingbox")
            }
            #if DEBUG
            .navigationDestination(isPresented: $openingModels) {
                ModelsView(viewModel: viewModel)
            }
            .task {
                if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_MODELS"] != nil {
                    openingModels = true
                }
            }
            #endif
        }
    }

    private func buttons(actions: ServiceActions) -> [CompactAction] {
        var buttons: [CompactAction] = []
        if actions.start != nil {
            buttons.append(CompactAction("Start", systemImage: "play.fill") {
                Task { await viewModel.start(service) }
            })
        }
        if actions.stop != nil {
            buttons.append(CompactAction("Stop", systemImage: "stop.fill", role: .destructive) {
                requestConfirm(.init(kind: .stop, serviceID: service.id,
                                     displayName: service.displayName))
            })
        }
        if actions.restart != nil {
            buttons.append(CompactAction("Restart", systemImage: "arrow.clockwise") {
                requestConfirm(.init(kind: .restart, serviceID: service.id,
                                     displayName: service.displayName))
            })
        }
        if service.updateSpec(viewModel.deployment.serviceContext).flavour == .composePull {
            buttons.append(CompactAction("Update", systemImage: "arrow.down.circle") {
                requestConfirm(.init(kind: .update, serviceID: service.id,
                                     displayName: service.displayName))
            })
        }
        if canReadLogs {
            buttons.append(CompactAction("Logs", systemImage: "text.alignleft") {
                requestLogs(service.id)
            })
        }
        switch actions.backup {
        case .wrapperScript:
            buttons.append(CompactAction("Backup", systemImage: "externaldrive.badge.plus") {
                requestBackup(service.id)
            })
        case .encryptedVolume:
            buttons.append(CompactAction("Backup", systemImage: "lock.doc") {
                requestPassphrase(service.id)
            })
        case nil:
            break
        }
        if actions.restore != nil {
            buttons.append(CompactAction("Restore", systemImage: "clock.arrow.circlepath",
                                         role: .destructive) {
                requestRestore(service.id)
            })
        }
        buttons.append(CompactAction("Remove", systemImage: "trash", role: .destructive) {
            requestUninstall(service.id)
        })
        return buttons
    }

    private var canReadLogs: Bool {
        service.actions(viewModel.deployment.serviceContext).logs != nil
    }

    /// One friendly line, and the containers behind it
    @ViewBuilder
    private var statusRows: some View {
        switch viewModel.serviceStatuses[service.id] ?? .idle {
        case .loaded(let containers):
            CollapsibleContainerList(containers: containers) { container, action in
                Task { await viewModel.controlContainer(container, action: action, service: service) }
            }
        case .loading:
            HStack { Text("Status"); Spacer(); ProgressView().controlSize(.small) }
        case .failed(let message):
            Label(message, systemImage: HealthLevel.critical.systemImageName)
                .font(.caption).foregroundStyle(.red)
        case .idle:
            Text("—").foregroundStyle(.secondary)
        }
    }
}

/// Opens or closes Vaultwarden's new-account sign-up
private struct VaultwardenSignupsRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onUpdate: (Deployment) -> Void
    @State private var confirmingOpen = false

    var body: some View {
        Toggle(isOn: Binding(
            get: { viewModel.deployment.serviceSettings.vaultwardenAllowSignups },
            set: { open in open ? (confirmingOpen = true) : apply(false) }
        )) {
            Text("Vaultwarden registration")
                .infoNote("Vaultwarden registration",
                          "When on, anyone who reaches the vault can create an account. Turn it on while you add people, then off again.")
        }
        .confirmationDialog("Open registration?", isPresented: $confirmingOpen, titleVisibility: .visible) {
            Button("Open", role: .destructive) { apply(true) }
                .dangerTint()
        } message: {
            Text("Anyone who can reach Vaultwarden can create an account until you close registration again.")
        }
    }

    private func apply(_ open: Bool) {
        Task {
            if let updated = await viewModel.setVaultwardenSignups(open) { onUpdate(updated) }
        }
    }
}
