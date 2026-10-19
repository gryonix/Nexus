import AgentControl
import ServerControl
import ServiceCatalog
import SwiftUI

struct ServiceBackupsView: View {
    let service: any ManagedService
    let state: Loadable<[BackupEntry]>
    let load: () async -> Void
    /// Downloads a backup by remote path for sharing
    let download: (String) async throws -> Data
    let pathFor: (BackupEntry) -> String?
    let delete: (BackupEntry) async -> Void
    /// Old data folders left by restores
    let copies: [PreRestoreCopy]
    let deleteCopy: (PreRestoreCopy) async -> Void

    @State private var expanded = false
    @State private var sharing: String?
    @State private var shareURL: URL?
    @State private var showingShareSheet = false
    @State private var shareError: String?
    @State private var pendingDeletion: BackupEntry?

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            content
        } label: {
            HStack {
                Label("Backups", systemImage: "externaldrive")
                Spacer()
                if case .loaded(let entries) = state, !entries.isEmpty {
                    Text(verbatim: "\(entries.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .onChange(of: expanded) { _, isOpen in
            guard isOpen, case .loaded = state else {
                if isOpen { Task { await load() } }
                return
            }
        }
        .shareSheet(isPresented: $showingShareSheet, items: shareURL.map { [$0] } ?? [])
        .alert("Delete this backup?",
               isPresented: Binding(get: { pendingDeletion != nil },
                                                 set: { if !$0 { pendingDeletion = nil } }),
                            presenting: pendingDeletion) { entry in
            Button("Delete", role: .destructive) {
                let target = entry
                pendingDeletion = nil
                Task { await delete(target) }
            }
            .dangerTint()
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { entry in
            Text(verbatim: BackupDeletionText.message(for: [entry]))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let shareError {
            Label(shareError, systemImage: HealthLevel.critical.systemImageName)
                .font(.caption)
                .foregroundStyle(.red)
        }
        switch state {
        case .loaded(let entries):
            if entries.isEmpty {
                Text("No backups")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries, id: \.name) { entry in
                    row(entry)
                }
            }
        case .loading, .idle:
            HStack { Text("Loading…"); Spacer(); ProgressView().controlSize(.small) }
        case .failed(let message):
            Label(message, systemImage: HealthLevel.critical.systemImageName)
                .font(.caption)
                .foregroundStyle(.red)
        }
        PreRestoreCopiesList(copies: copies, delete: deleteCopy)
    }

    private func row(_ entry: BackupEntry) -> some View {
        let path = pathFor(entry)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(entry.sizeText) · \(entry.dateText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if let drive = entry.drive {
                    Label(UIL10n.string("On the drive %@", drive), systemImage: "externaldrive")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if sharing == entry.name {
                ProgressView().controlSize(.small)
            } else if let path, entry.isDirectory == false, entry.drive == nil {
                Button {
                    share(entry, path: path)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .glassIconButtonStyle()
            }
            Button(role: .destructive) {
                pendingDeletion = entry
            } label: {
                Image(systemName: "trash")
            }
            .dangerTint()
            .glassIconButtonStyle()
            .disabled(path == nil)
        }
    }

    private func share(_ entry: BackupEntry, path: String) {
        sharing = entry.name
        shareError = nil
        Task { @MainActor in
            defer { sharing = nil }
            do {
                shareURL = try await BackupSharing.stage(path: path, download: download)
                showingShareSheet = true
            } catch {
                shareError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }
}
