import ServerControl
import ServiceCatalog
import SwiftUI

/// One listed backup, restored here or on another server
struct RestoreBackupSheet: View {
    let row: FleetBackup
    @ObservedObject var model: ServerBackupsModel
    let onClose: () -> Void

    @State private var targetID: UUID
    @State private var passphrase = ""
    @State private var confirming = false
    @State private var isWorking = false
    @State private var failure: String?

    init(row: FleetBackup, model: ServerBackupsModel, onClose: @escaping () -> Void) {
        self.row = row
        self.model = model
        self.onClose = onClose
        _targetID = State(initialValue: model.dashboard.deployment.id)
    }

    private var targets: [Deployment] { model.restoreTargets(for: row) }
    private var target: Deployment? { targets.first { $0.id == targetID } }
    private var needsPassphrase: Bool { target.map { model.needsPassphrase(row, on: $0) } ?? false }
    private var canStart: Bool { target != nil && !isWorking && (!needsPassphrase || !passphrase.isEmpty) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Restoring replaces the service's current data. Its containers go down while it runs.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
                targetSection
                if needsPassphrase {
                    Section("Backup passphrase") {
                        SecureField("Passphrase", text: $passphrase)
                            .textContentType(.password)
                    }
                }
                if let failure {
                    Label(failure, systemImage: HealthLevel.critical.systemImageName)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Restore \(row.serviceName)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { confirming = true } label: {
                    Group {
                        if isWorking { ProgressView() } else { Text("Restore").font(.headline) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .prominentActionButtonStyle()
                .controlSize(.large)
                .disabled(!canStart)
                .padding()
            }
            .alert("Restore and replace the current data?", isPresented: $confirming) {
                Button("Restore", role: .destructive) { start() }
                    .dangerTint()
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Everything the service holds now is replaced by the backup. This cannot be undone.")
            }
        }
        .interactiveDismissDisabled(isWorking)
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 380)
        #endif
    }

    private var targetSection: some View {
        Section {
            Picker("Restore to", selection: $targetID) {
                ForEach(targets) { server in
                    Text(verbatim: server.name).tag(server.id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Restore to")
        } footer: {
            if targetID != row.serverID {
                Text("The backup goes from \(row.serverName) through this device to the chosen server.")
            }
        }
    }

    private func start() {
        guard let target else { return }
        isWorking = true
        failure = nil
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await model.restore(row, on: target, passphrase: needsPassphrase ? passphrase : nil)
                onClose()
            } catch {
                failure = DashboardViewModel.message(for: error)
            }
        }
    }
}

extension ServerBackupsModel {
    /// Servers running the same service, this one first
    func restoreTargets(for row: FleetBackup) -> [Deployment] {
        guard let service = ServiceRegistry.service(ServiceID(rawValue: row.serviceID)) else { return [] }
        let here = dashboard.deployment
        guard canRestore(row) else { return [] }
        let others = canShare(row) ? fleet().filter { server in
            server.id != here.id && server.services.contains(service.id)
                && service.actions(server.serviceContext).restore != nil
        } : []
        return [here] + others.sorted { $0.name < $1.name }
    }

    func canRestore(_ row: FleetBackup) -> Bool {
        guard let service = ServiceRegistry.service(ServiceID(rawValue: row.serviceID)),
              dashboard.deployment.services.contains(service.id) else { return false }
        return service.actions(dashboard.deployment.serviceContext).restore != nil
    }

    func needsPassphrase(_ row: FleetBackup, on server: Deployment) -> Bool {
        guard let service = ServiceRegistry.service(ServiceID(rawValue: row.serviceID)) else { return false }
        return service.actions(server.serviceContext).restore?.needsPassphrase(for: row.entry.name) ?? false
    }

    /// Another server gets the archive through this device
    func restore(_ row: FleetBackup, on server: Deployment, passphrase: String?) async throws {
        guard let service = ServiceRegistry.service(ServiceID(rawValue: row.serviceID)) else { return }
        let source = dashboard
        if server.id == source.deployment.id {
            let path = try await source.restorePath(service, entry: row.entry)
            Task { await source.runRestore(service, from: .serverPath(path), passphrase: passphrase) }
            return
        }
        let limit = Self.copyLimit
        if let size = row.entry.sizeBytes, size > limit {
            throw ServerControlError.notConfigured(Self.tooLarge(size, limit: limit))
        }
        guard let path = source.backupPath(service, entry: row.entry) else { return }
        let data = try await source.downloadBackup(service, at: path)
        let target = makeDashboard(server)
        Task {
            await target.runRestore(service, from: .deviceFile(data: data, fileName: row.entry.displayName),
                                    passphrase: passphrase)
        }
    }

    /// What passes through the device both ways
    static var copyLimit: Int64 {
        min(Int64(FileBrowserViewModel.downloadLimit), Int64(ServiceOperations.uploadLimitBytes))
    }

    private static func tooLarge(_ size: Int64, limit: Int64) -> String {
        UIL10n.string("This backup is %@; copying between servers is limited to %@.",
                      ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                      ByteCountFormatter.string(fromByteCount: limit, countStyle: .file))
    }
}

extension DashboardViewModel {
    /// Where the restore script finds this listed backup
    func restorePath(_ service: any ManagedService, entry: BackupEntry) async throws -> String {
        let (ops, _) = try await operations(for: service)
        guard let spec = ops.restoreSpec, !entry.name.hasPrefix("/") else { return entry.name }
        return "\(spec.backupDir)/\(entry.name)"
    }
}
