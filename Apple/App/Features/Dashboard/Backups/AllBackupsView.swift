import ServerControl
import SwiftUI

/// Every backup of this server and its drives, newest first
struct AllBackupsView: View {
    @ObservedObject var model: ServerBackupsModel

    @State private var filter = BackupFilter()
    @State private var pendingDeletion: [FleetBackup] = []
    @State private var sharing: Set<String> = []
    @State private var shareURLs: [URL] = []
    @State private var showingShareSheet = false
    @State private var shareError: String?
    @State private var choosing = false
    @State private var selected: Set<String> = []
    @State private var restoring: FleetBackup?

    private var shown: [FleetBackup] { BackupOverview.filtered(model.rows, by: filter) }
    private var selectable: [FleetBackup] { shown.filter(model.canDelete) }
    private var selectedRows: [FleetBackup] { model.rows.filter { selected.contains($0.id) } }

    var body: some View {
        Form {
            BackupFilterSection(model: model, filter: $filter)
            if choosing { selectionSection }
            Section {
                BackupProblemRow(model: model)
                errorRows
                if shown.isEmpty { emptyRow }
                ForEach(shown) { row in
                    BackupRow(row: row, canDelete: model.canDelete(row), canShare: model.canShare(row),
                              canRestore: model.canRestore(row),
                              isSharing: sharing.contains(row.id),
                              isSelected: choosing ? selected.contains(row.id) : nil,
                              share: { share([row]) }, delete: { pendingDeletion = [row] },
                              toggle: { toggle(row) }, restore: { restoring = row })
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .bottomBarClearance()
        .navigationTitle("All backups")
        .raisedNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(choosing ? "Done" : "Select") { toggleChoosing() }
                    .disabled(model.rows.isEmpty && !choosing)
            }
        }
        .refreshable { await model.load() }
        .task { if !model.hasLoaded { await model.load() } }
        .shareSheet(isPresented: $showingShareSheet, items: shareURLs)
        .sheet(item: $restoring) { row in
            RestoreBackupSheet(row: row, model: model) { restoring = nil }
        }
        .alert(pendingDeletion.count == 1 ? "Delete this backup?" : "Delete permanently?",
               isPresented: Binding(get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } })) {
            Button("Delete", role: .destructive) { confirmDeletion() }
                .dangerTint()
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text(deletionMessage)
        }
    }

    private var deletionMessage: String {
        BackupDeletionText.message(for: pendingDeletion.map(\.entry))
    }

    private var selectionSection: some View {
        BackupSelectionSection(
            selected: selected.count,
            shareable: selectedRows.filter(model.canShare).count,
            selectable: selectable.count,
            isWorking: !sharing.isEmpty,
            selectAll: { selected = selected.count == selectable.count ? [] : Set(selectable.map(\.id)) },
            share: { share(selectedRows.filter(model.canShare)) },
            delete: { pendingDeletion = selectedRows })
    }

    @ViewBuilder private var errorRows: some View {
        ForEach([shareError, model.actionError].compactMap { $0 }, id: \.self) { message in
            Label(message, systemImage: HealthLevel.critical.systemImageName)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder private var emptyRow: some View {
        if model.isLoading {
            HStack { Text("Loading…"); Spacer(); ProgressView().controlSize(.small) }
        } else {
            Text("No backups yet.").foregroundStyle(.secondary)
        }
    }

    private func toggleChoosing() {
        choosing.toggle()
        selected = []
    }

    private func toggle(_ row: FleetBackup) {
        if selected.contains(row.id) { selected.remove(row.id) } else { selected.insert(row.id) }
    }

    private func confirmDeletion() {
        let rows = pendingDeletion
        pendingDeletion = []
        selected.subtract(rows.map(\.id))
        Task { await model.deleteMany(rows) }
    }

    private func share(_ rows: [FleetBackup]) {
        sharing = Set(rows.map(\.id))
        shareError = nil
        Task { @MainActor in
            defer { sharing = [] }
            do {
                let urls = try await model.downloadMany(rows)
                guard !urls.isEmpty else { return }
                shareURLs = urls
                showingShareSheet = true
            } catch {
                shareError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
