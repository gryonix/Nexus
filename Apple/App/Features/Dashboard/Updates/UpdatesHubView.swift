import ServerControl
import ServiceCatalog
import SwiftUI

/// Everything about updates in one place
struct UpdatesHubView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        Form {
            UpdateNumbersSection(viewModel: viewModel)
            actionsSection
            settingsSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .screenTitle("Updates")
        .raisedNavigationTitle()
        .refreshable { await refresh() }
        .task { await load() }
    }

    private func load() async {
        await viewModel.loadAutoUpdate()
        await viewModel.loadBackupParts()
        if viewModel.updateReports.isEmpty { await viewModel.checkForUpdates() }
    }

    private func refresh() async {
        await viewModel.loadAutoUpdate()
        await viewModel.checkForUpdates()
    }

    private var actionsSection: some View {
        Section {
            NavigationLink {
                UpdateServicesView(viewModel: viewModel)
            } label: {
                Label("All services", systemImage: "list.bullet.rectangle")
            }
            checkButton
            updateAllButton
        }
    }

    private var checkButton: some View {
        Button {
            Task { await viewModel.checkForUpdates() }
        } label: {
            if viewModel.checkingUpdates {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking…") }
            } else {
                Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .disabled(viewModel.checkingUpdates)
    }

    /// Services with a newer image, one after another
    private var waitingServices: [any ManagedService] {
        UpdateSummary.rowIDs(viewModel).compactMap { id in
            guard case .available = viewModel.updateReports[id] else { return nil }
            return UpdateSummary.service(id, in: viewModel)
        }
    }

    @ViewBuilder private var updateAllButton: some View {
        let waiting = waitingServices
        if !waiting.isEmpty {
            Button {
                Task { for service in waiting { await viewModel.runUpdateNow(service) } }
            } label: {
                Label(UIL10n.string("Update all (%lld)", waiting.count), systemImage: "arrow.down.circle")
            }
        }
    }

    private var settingsSection: some View {
        Section {
            NavigationLink {
                UpdateScheduleView(viewModel: viewModel)
            } label: {
                LabeledContent {
                    Text(ScheduleFields.summary(viewModel.autoUpdate.schedule)).foregroundStyle(.secondary)
                } label: {
                    Label("Scheduled updates", systemImage: "clock.arrow.2.circlepath")
                }
            }
            NavigationLink {
                BackupPartsView(viewModel: viewModel, scope: .beforeUpdate)
            } label: {
                LabeledContent {
                    Text(BackupPartText.summary(viewModel.backupParts.choice.beforeUpdate))
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Copy before updating", systemImage: "externaldrive.badge.checkmark")
                }
            }
            NavigationLink {
                SystemUpdatePage(viewModel: viewModel)
            } label: {
                Label("System update", systemImage: "gearshape.arrow.triangle.2.circlepath")
            }
            if viewModel.deployment.usesAgent {
                NavigationLink {
                    AgentUpdatesPage(viewModel: viewModel)
                } label: {
                    Label("Agent updates", systemImage: "cpu")
                }
            }
        }
    }
}

/// How many services wait, and when updates last ran
struct UpdateNumbersSection: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        Section {
            if viewModel.updateReports.isEmpty {
                emptyRow
            } else {
                LabeledContent("Updates waiting") {
                    Text("\(UpdateSummary.waiting(viewModel))").monospacedDigit()
                        .foregroundStyle(UpdateSummary.waiting(viewModel) > 0 ? .orange : .secondary)
                }
                LabeledContent("Up to date") {
                    Text("\(UpdateSummary.current(viewModel))").monospacedDigit()
                }
            }
            if let lastRun = viewModel.updateRunLog.lastRun {
                LabeledContent("Last scheduled run") {
                    Text(lastRun.formatted(date: .abbreviated, time: .shortened))
                }
            }
            if let error = viewModel.autoUpdateError {
                Label(error, systemImage: HealthLevel.critical.systemImageName)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder private var emptyRow: some View {
        if viewModel.checkingUpdates {
            HStack { Text("Checking…"); Spacer(); ProgressView().controlSize(.small) }
        } else {
            Text("Not checked").foregroundStyle(.secondary)
        }
    }
}

/// The agent's own updates, on a page of their own
struct AgentUpdatesPage: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        Form {
            AgentSelfUpdateSection(viewModel: viewModel)
            AgentOpeningCheckRow(deploymentID: viewModel.deployment.id)
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .bottomBarClearance()
        .screenTitle("Agent updates")
        .raisedNavigationTitle()
        .task { await viewModel.loadSelfUpdateStatus() }
    }
}
