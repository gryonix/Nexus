import ServerControl
import ServiceCatalog
import SwiftUI

/// Edits when and what is updated on a schedule
struct UpdateScheduleView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var draft = AutoUpdateSettings()
    @State private var loaded = false
    @State private var isSaving = false
    @StateObject private var edits = PendingRowEdits()

    /// Tells the bar whether the schedule waits
    private func offerEdit() {
        let edit = PendingRowEdits.Edit(
            id: "update-schedule", text: .schedule,
            apply: {
                await save()
                return viewModel.autoUpdateError == nil
            },
            revert: { draft = viewModel.autoUpdate })
        let valid = !(draft.isOn && draft.services.isEmpty)
        edits.offer(edit, changed: PendingRules.waits(draft, saved: viewModel.autoUpdate, valid: loaded && valid))
    }

    var body: some View {
        Form {
            Section {
                Toggle("Update automatically", isOn: Binding(
                    get: { draft.schedule.isOn },
                    set: { draft.schedule = $0 ? ScheduleFields.defaultOn : .off }))
                if loaded, draft.isOn { ScheduleFields(schedule: $draft.schedule) }
            }
            if draft.isOn { servicesSection }
            saveSection
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .screenTitle("Scheduled updates")
        .raisedNavigationTitle()
        .task {
            await viewModel.loadAutoUpdate()
            draft = viewModel.autoUpdate
            loaded = true
        }
        .onChange(of: draft) { offerEdit() }
        .pendingRowEdits(edits)
    }

    private var servicesSection: some View {
        Section {
            ForEach(UpdateSummary.updatable(viewModel), id: \.id) { service in
                Toggle(viewModel.title(of: service), isOn: binding(for: service.id))
            }
        } footer: {
            Text("An update can break a service. Before each one the server takes a backup, and if the service does not come back up it is rolled back to the image it was running. Configuration changes an update makes to its own data are not undone by that.")
        }
    }

    private var saveSection: some View {
        Section {
            if let error = viewModel.autoUpdateError {
                Label(error, systemImage: HealthLevel.critical.systemImageName)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func binding(for id: ServiceID) -> Binding<Bool> {
        Binding(
            get: { draft.services.contains(id.rawValue) },
            set: { isOn in
                if isOn { draft.services.insert(id.rawValue) } else { draft.services.remove(id.rawValue) }
            })
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        await viewModel.saveAutoUpdate(draft)
        draft = viewModel.autoUpdate
    }
}
