import ServerControl
import ServiceCatalog
import SwiftUI

/// Everything about backups in one place
struct BackupsHubView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let requests: BackupRequests

    @StateObject private var backups: ServerBackupsModel
    @State private var showingDestination = false
    @State private var choosingBackup = false
    @State private var pendingBackup: BackupNowChoice?

    init(viewModel: DashboardViewModel, requests: BackupRequests) {
        self.viewModel = viewModel
        self.requests = requests
        _backups = StateObject(wrappedValue: ServerBackupsModel(dashboard: viewModel))
    }

    var body: some View {
        Form {
            BackupNumbersSection(model: backups)
            Section {
                NavigationLink {
                    AllBackupsView(model: backups)
                } label: {
                    Label("All backups", systemImage: "list.bullet.rectangle")
                }
                backUpNowButton
                restoreMenu
            }
            settingsSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .navigationTitle("Backups")
        .raisedNavigationTitle()
        .refreshable { await refresh() }
        .task { await backups.load() }
        .task { await refreshSettings() }
        .navigationDestination(isPresented: $showingDestination) {
            BackupDestinationView(viewModel: viewModel)
        }
        .sheet(isPresented: $choosingBackup, onDismiss: startPendingBackup) {
            BackupNowSheet(viewModel: viewModel,
                           onCancel: { choosingBackup = false },
                           onConfirm: { choice in
                               pendingBackup = choice
                               choosingBackup = false
                           })
        }
        #if DEBUG
        .task { await openDestinationForScreenshots() }
        .task { await openRestoreForScreenshots() }
        #endif
    }

    private func refresh() async {
        async let settings: Void = refreshSettings()
        await backups.load()
        await settings
    }

    private func refreshSettings() async {
        await viewModel.loadAutoBackup()
        await viewModel.loadBackupDestination()
    }

    private var backUpNowButton: some View {
        Button {
            choosingBackup = true
        } label: {
            Label("Back up now", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(backupCapableServices.isEmpty)
    }

    /// Runs the chosen backups once the sheet is gone
    private func startPendingBackup() {
        guard let choice = pendingBackup else { return }
        pendingBackup = nil
        Task {
            await viewModel.runBackups(choice)
            await backups.load()
        }
    }

    @ViewBuilder private var restoreMenu: some View {
        let restorable = viewModel.services.filter {
            $0.actions(viewModel.deployment.serviceContext).restore != nil
        }
        if !restorable.isEmpty {
            Menu {
                ForEach(restorable, id: \.id) { service in
                    Button(service.displayName) { requests.restore(service.id) }
                }
            } label: {
                Label("Restore", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    private var backupCapableServices: [any ManagedService] {
        viewModel.services.filter { $0.actions(viewModel.deployment.serviceContext).backup != nil }
    }

    private var settingsSection: some View {
        Section {
            NavigationLink {
                BackupScheduleView(viewModel: viewModel)
            } label: {
                LabeledContent {
                    Text(BackupScheduleSummary.text(viewModel.autoBackup.schedule))
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Scheduled backups", systemImage: "clock.arrow.2.circlepath")
                }
            }
            NavigationLink {
                BackupDestinationView(viewModel: viewModel)
            } label: {
                LabeledContent {
                    Text(destinationSummary).foregroundStyle(destinationColor)
                } label: {
                    Label("Backup destination", systemImage: "externaldrive.badge.icloud")
                }
            }
            if viewModel.deployment.hasPhysicalAccess {
                NavigationLink {
                    BackupDrivesView(viewModel: viewModel)
                } label: {
                    Label("USB drives", systemImage: "externaldrive")
                }
            }
        }
    }

    private var destinationColor: Color {
        let state = viewModel.backupDestination
        return state.lastShipment != nil && !state.lastShipmentSucceeded ? .orange : .secondary
    }

    private var destinationSummary: String {
        let state = viewModel.backupDestination
        guard state.settings.kind != .none else { return UIL10n.string("This server only") }
        if state.lastShipment != nil, !state.lastShipmentSucceeded {
            return UIL10n.string("Last copy failed")
        }
        switch state.settings.kind {
        case .ssh: return state.settings.host
        case .s3: return state.settings.bucket
        case .none: return UIL10n.string("This server only")
        }
    }

    #if DEBUG
    private func openRestoreForScreenshots() async {
        guard let service = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_RESTORE"] else { return }
        try? await Task.sleep(for: .milliseconds(1500))
        requests.restore(ServiceID(rawValue: service))
    }

    private func openDestinationForScreenshots() async {
        guard ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_BACKUP_DESTINATION"] != nil
        else { return }
        try? await Task.sleep(for: .milliseconds(1800))
        showingDestination = true
    }
    #endif
}
