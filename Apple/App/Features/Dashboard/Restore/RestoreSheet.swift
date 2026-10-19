import ServerControl
import ServiceCatalog
import SwiftUI
import UniformTypeIdentifiers

struct RestoreSheet: View {
    let service: any ManagedService
    let needsPassphrase: Bool
    /// Loads the server-side listing
    let loadBackups: () async throws -> [DashboardViewModel.RestorableBackup]
    let onCancel: () -> Void
    let onChoose: (DashboardViewModel.RestoreSource, String?) -> Void

    @State private var backups: [DashboardViewModel.RestorableBackup] = []
    @State private var place = BackupFilter.Place.any
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var passphrase = ""
    @State private var showFileImporter = false
    @State private var importError: String?

    private var passphraseValue: String? { needsPassphrase ? passphrase : nil }
    private var canContinue: Bool { !needsPassphrase || !passphrase.isEmpty }
    private var shownBackups: [DashboardViewModel.RestorableBackup] {
        backups.filter { place.admits($0.entry) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Restoring replaces the service's current data. Its containers go down while it runs.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                if needsPassphrase {
                    Section("Backup passphrase") {
                        SecureField("Passphrase", text: $passphrase)
                            .textContentType(.password)
                        Text("The passphrase this backup was encrypted with. Without it the archive cannot be opened.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Backups") {
                    BackupPlacePicker(place: $place)
                    if isLoading {
                        HStack { Text("Loading…"); Spacer(); ProgressView().controlSize(.small) }
                    } else if let loadError {
                        Label(loadError, systemImage: HealthLevel.critical.systemImageName)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if shownBackups.isEmpty {
                        Text("No backups")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(shownBackups) { backup in
                            Button {
                                onChoose(.serverPath(backup.path), passphraseValue)
                            } label: {
                                backupRow(backup.entry)
                            }
                            .disabled(!canContinue)
                        }
                    }
                }

                Section {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Choose a file from this device…", systemImage: "arrow.up.doc")
                    }
                    .disabled(!canContinue)
                    if let importError {
                        Label(importError, systemImage: HealthLevel.critical.systemImageName)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    InfoSectionHeader("From this device", note: "The file is uploaded to the server before the restore starts. Very large backups are better restored from the list above — they never have to leave the server.")
                }
            }
            .navigationTitle("Restore \(service.displayName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.data],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .task { await load() }
        }
    }

    private func backupRow(_ entry: BackupEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.displayName)
                .font(.callout)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            backups = try await loadBackups()
            loadError = nil
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    /// Hands the picked file to the restore flow
    private func handleImport(_ result: Result<[URL], Error>) {
        importError = nil
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result {
                importError = error.localizedDescription
            }
            return
        }
        Task { @MainActor in
            do {
                let data = try await Self.readBackupFile(at: url)
                onChoose(.deviceFile(data: data, fileName: url.lastPathComponent), passphraseValue)
            } catch ServerControlError.fileTooLarge(_, let size, let limit) {
                importError = UIL10n.string(
                    "This backup is %@ — uploads from the device are limited to %@. Restore it from the list on the server instead.",
                    Self.sizeText(size), Self.sizeText(limit))
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    /// Reads the picked file into memory off the main actor
    private static func readBackupFile(at url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let limit = ServiceOperations.uploadLimitBytes
            if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > limit {
                throw ServerControlError.fileTooLarge(path: url.lastPathComponent,
                                                      size: UInt64(size), limit: UInt64(limit))
            }
            return try Data(contentsOf: url)
        }.value
    }

    private static func sizeText(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
