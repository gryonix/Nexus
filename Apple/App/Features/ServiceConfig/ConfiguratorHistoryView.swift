import ServiceCatalog
import SwiftUI

/// History of generated configurations
struct ConfiguratorHistoryView: View {
    let topology: Topology?
    var scope: DeploymentScope? = nil
    /// Local copy so deletions reflect immediately inside the sheet
    @State var entries: [ConfiguratorDraft]
    let onRestore: (ConfiguratorDraft) -> Void
    let onDelete: (Set<UUID>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingClear = false
    @State private var editing = false
    @State private var selection: Set<UUID> = []

    private var scenarioEntries: [ConfiguratorDraft] {
        guard let topology else { return entries }
        return entries.filter { $0.topology == topology
            && (scope == nil || $0.localOnly == (scope == .localOnly)) }
    }

    var body: some View {
        NavigationStack {
            historyContent
                .navigationTitle("History")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { historyToolbar }
                .alert(clearHistoryConfirmationTitle,
                       isPresented: $confirmingClear) {
                    Button("Clear History", role: .destructive) {
                        delete(ids: Set(scenarioEntries.map(\.id)))
                    }
                    .dangerTint()
                    Button("Cancel", role: .cancel) {}
                }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 320)
        #endif
    }

    @ViewBuilder
    private var historyContent: some View {
        Group {
            if scenarioEntries.isEmpty {
                ContentUnavailableView {
                    Label("No saved configurations yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Every generated configuration is saved here so you can reopen it later.")
                }
            } else {
                List(selection: $selection) {
                    ForEach(scenarioEntries) { entry in
                        Button {
                            onRestore(entry)
                            dismiss()
                        } label: {
                            row(entry)
                        }
                        .buttonStyle(.plain)
                        // macOS has no swipe-to-delete; the menu covers it.
                        .contextMenu {
                            Button(role: .destructive) {
                                delete(ids: [entry.id])
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .dangerTint()
                        }
                    }
                    .onDelete { offsets in
                        delete(ids: Set(offsets.map { scenarioEntries[$0].id }))
                    }
                }
                #if os(iOS)
                .environment(\.editMode, .constant(editing ? .active : .inactive))
                #endif
            }
        }
    }

    @ToolbarContentBuilder
    private var historyToolbar: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) { clearHistoryButton }
        #else
        ToolbarItem(placement: .destructiveAction) { clearHistoryButton }
        if !selection.isEmpty {
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) {
                    delete(ids: selection)
                    selection.removeAll()
                } label: {
                    Text("Delete (\(selection.count))")
                }
                .dangerTint()
            }
        }
        #endif
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
        }
        #if os(iOS)
        ToolbarItemGroup(placement: .bottomBar) {
            if editing {
                Button("Cancel") {
                    editing = false
                    selection.removeAll()
                }
                Spacer()
                Button(role: .destructive) {
                    delete(ids: selection)
                    selection.removeAll()
                    editing = false
                } label: {
                    Text("Delete (\(selection.count))")
                }
                .dangerTint()
                .disabled(selection.isEmpty)
            } else {
                Button("Select") { editing = true }
                    .disabled(scenarioEntries.isEmpty)
                Spacer()
            }
        }
        #endif
    }

    private var clearHistoryConfirmationTitle: LocalizedStringKey {
        topology == nil
            ? "Delete all saved configurations?"
            : "Delete all saved configurations for this scenario?"
    }

    private var clearHistoryButton: some View {
        Button(role: .destructive) {
            confirmingClear = true
        } label: {
            Label("Clear History", systemImage: "trash")
        }
        .dangerTint()
        .disabled(scenarioEntries.isEmpty)
    }

    private func delete(ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
        onDelete(ids)
    }

    private func row(_ entry: ConfiguratorDraft) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if entry.domain.isEmpty {
                Text("Untitled configuration")
                    .font(.headline)
            } else {
                Text(verbatim: entry.domain)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 6) {
                Text(entry.savedAt, format: .dateTime.day().month().year().hour().minute())
                serviceIcons(entry)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private func serviceIcons(_ entry: ConfiguratorDraft) -> some View {
        var ids = entry.extraServices
        if entry.mailEnabled { ids.insert(ServiceID(rawValue: entry.mailEngineID)) }
        if entry.vpnEnabled { ids.formUnion(entry.vpnProtocols) }
        return HStack(spacing: 4) {
            ForEach(ids.sorted(), id: \.rawValue) { id in
                Image(systemName: ServiceRegistry.service(id)?.systemImage ?? "shippingbox")
            }
        }
    }
}
