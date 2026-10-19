import ServerControl
import ServiceCatalog
import SwiftUI

struct AutoUpdateSection: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var expanded = false
    @State private var draft = AutoUpdateSettings()
    @State private var isSaving = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                content
            } label: {
                HStack {
                    Label("Updates", systemImage: "arrow.down.circle")
                    Spacer()
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: expanded) { _, isOpen in
                guard isOpen else { return }
                Task {
                    await viewModel.loadAutoUpdate()
                    draft = viewModel.autoUpdate
                }
            }
        }
    }

    private var statusRowIDs: [ServiceID] {
        UpdateRows.statusRows(
            updatable: updatableServices.map(\.id),
            deploymentServices: viewModel.deployment.services,
            reported: viewModel.updateReports.keys)
    }

    /// The badge on the closed row
    private var summary: String {
        let waiting = statusRowIDs.filter {
            if case .available = viewModel.updateReports[$0] { return true }
            return false
        }.count
        if waiting > 0 { return UIL10n.string("%@ waiting", "\(waiting)") }
        return ScheduleFields.summary(viewModel.autoUpdate.schedule)
    }

    @ViewBuilder
    private var content: some View {
        Button {
            Task { await viewModel.checkForUpdates() }
        } label: {
            if viewModel.checkingUpdates {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking…") }
            } else {
                Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .rowActionButtonStyle()
        .disabled(viewModel.checkingUpdates)

        ForEach(statusRowIDs, id: \.self) { id in
            statusRow(for: id)
        }

        lastRunSection

        Toggle("Update automatically", isOn: Binding(
            get: { draft.schedule.isOn },
            set: { draft.schedule = $0 ? ScheduleFields.defaultOn : .off }
        ))

        scheduleFields

        Button {
            save()
        } label: {
            if isSaving {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Saving…") }
            } else {
                Text("Save schedule")
            }
        }
        .rowActionButtonStyle()
        .disabled(isSaving || (draft.isOn && draft.services.isEmpty))

        if let error = viewModel.autoUpdateError {
            Label(error, systemImage: HealthLevel.critical.systemImageName)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var scheduleFields: some View {
        if draft.isOn {
            ScheduleFields(schedule: $draft.schedule)

            ForEach(updatableServices, id: \.id) { service in
                Toggle(service.displayName, isOn: binding(for: service.id))
            }

            Text("An update can break a service. Before each one the server takes a backup, and if the service does not come back up it is rolled back to the image it was running. Configuration changes an update makes to its own data are not undone by that.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func statusRow(for id: ServiceID) -> some View {
        let status = viewModel.updateReports[id]
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: displayName(for: id))
                if let record = viewModel.updateRunLog.records.last(where: { $0.service == id }) {
                    lastRunCaption(record.outcome)
                }
            }
            Spacer()
            switch status {
            case .available(let images):
                VStack(alignment: .trailing, spacing: 1) {
                    Text("Update available").foregroundStyle(.orange)
                    Text(verbatim: images.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if let service = resolvedService(id) {
                        Button("Update now") {
                            Task { await viewModel.runUpdateNow(service) }
                        }
                        .rowActionButtonStyle()
                        .font(.caption2)
                    }
                }
            case .current:
                Text("Up to date").foregroundStyle(.secondary)
            case .selfManaged:
                Text("Updates itself").foregroundStyle(.secondary)
            case .rebuiltBySetup:
                Text("Moves with the app").foregroundStyle(.secondary)
            case .unknown:
                Text("Could not check").foregroundStyle(.orange)
            case nil:
                Text("Not checked").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private var lastRunSection: some View {
        if !viewModel.updateRunLog.isEmpty {
            if let lastRun = viewModel.updateRunLog.lastRun {
                Text("Last scheduled run: \(lastRun.formatted(.dateTime.day().month().year().hour().minute()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// How the last update of a service ended
    @ViewBuilder
    private func lastRunCaption(_ outcome: ServiceUpdateRunRecord.Outcome) -> some View {
        Group {
            switch outcome {
            case .updated:
                Text("Last update: done").foregroundStyle(.secondary)
            case .rolledBack(let reason):
                Text("Last update rolled back: \(reason)").foregroundStyle(.orange)
            case .failed(let reason):
                Text("Last update failed: \(reason)").foregroundStyle(.orange)
            }
        }
        .font(.caption2)
        .lineLimit(2)
        .truncationMode(.middle)
    }

    private func displayName(for id: ServiceID) -> String {
        resolvedService(id)?.displayName ?? id.rawValue
    }

    private func resolvedService(_ id: ServiceID) -> (any ManagedService)? {
        viewModel.services.first { $0.id == id } ?? ServiceRegistry.service(id)
    }

    /// Services whose images this server can actually pull
    private var updatableServices: [any ManagedService] {
        viewModel.services.filter {
            $0.updateSpec(viewModel.deployment.serviceContext).flavour != .builtOnServer
        }
    }

    private func binding(for id: ServiceID) -> Binding<Bool> {
        Binding(
            get: { draft.services.contains(id.rawValue) },
            set: { isOn in
                if isOn { draft.services.insert(id.rawValue) }
                else { draft.services.remove(id.rawValue) }
            }
        )
    }

    private func save() {
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            await viewModel.saveAutoUpdate(draft)
            draft = viewModel.autoUpdate
        }
    }
}
