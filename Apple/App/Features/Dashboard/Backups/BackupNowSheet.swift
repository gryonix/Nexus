import ServerControl
import ServiceCatalog
import SwiftUI

/// Picks several services to back up now, and the key
struct BackupNowSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onCancel: () -> Void
    let onConfirm: (BackupNowChoice) -> Void

    @State private var choice = BackupNowChoice()
    @State private var estimates: [String: BackupEstimate] = [:]
    @State private var estimating: Set<String> = []
    @State private var hasStoredKey: Bool?

    private var services: [any ManagedService] {
        viewModel.services.filter { backup(of: $0) != nil }
    }

    private var defaultsOn: Set<String> {
        Set(services.filter { backup(of: $0)?.encryptsByDefault == true }.map(\.id.rawValue))
    }

    private var alwaysEncrypted: Set<String> {
        Set(services.filter { backup(of: $0)?.wrapper == nil }.map(\.id.rawValue))
    }

    private var total: BackupEstimate? {
        BackupNowChoice.total(choice.services.compactMap { estimates[$0] })
    }

    var body: some View {
        NavigationStack {
            Form {
                BackupNowServicesSection(services: services, chosen: choice.services, select: select)
                BackupNowSizeSection(total: total, isLoading: !estimating.isEmpty)
                BackupNowKeySection(choice: $choice, defaultsOn: defaultsOn, alwaysEncrypted: alwaysEncrypted,
                                    alwaysEncryptedNames: alwaysEncryptedNames, hasStoredKey: hasStoredKey)
            }
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 440, minHeight: 480)
            #endif
            .navigationTitle("Back up now")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbar }
            .task { await loadStoredKey() }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(UIL10n.string("Back Up (%lld)", choice.services.count)) { onConfirm(choice) }
                .disabled(!choice.isReady(defaultsOn: defaultsOn, alwaysEncrypted: alwaysEncrypted,
                                          hasStoredKey: hasStoredKey))
        }
    }

    private var alwaysEncryptedNames: [String] {
        services.filter { alwaysEncrypted.contains($0.id.rawValue) && choice.services.contains($0.id.rawValue) }
            .map(\.displayName)
    }

    private func backup(of service: any ManagedService) -> BackupSpec? {
        service.actions(viewModel.deployment.serviceContext).backup
    }

    /// Ticks or unticks services, sizing newly ticked ones
    private func select(_ ids: [String]) {
        for id in ids { choice.toggle(id) }
        for id in ids where choice.services.contains(id) && estimates[id] == nil {
            guard let service = services.first(where: { $0.id.rawValue == id }), backup(of: service)?.wrapper != nil
            else { continue }
            estimating.insert(id)
            Task {
                defer { estimating.remove(id) }
                estimates[id] = try? await viewModel.estimateBackup(service)
            }
        }
    }

    private func loadStoredKey() async {
        if DemoFleet.covers(viewModel.deployment) {
            hasStoredKey = true
            return
        }
        guard let state = try? await viewModel.autoBackupSeam().loadDrives(), state.supported else { return }
        hasStoredKey = state.hasPassphrase
        if !state.hasPassphrase { choice.key = .typed }
    }
}

/// The services, each with a tick
private struct BackupNowServicesSection: View {
    let services: [any ManagedService]
    let chosen: [String]
    let select: ([String]) -> Void

    private var allChosen: Bool { chosen.count == services.count }

    var body: some View {
        Section {
            ForEach(services, id: \.id) { service in
                serviceRow(service)
            }
        } header: {
            HStack {
                Text("Services")
                Spacer()
                Button(allChosen ? "Deselect all" : "Select all") { toggleAll() }
                    .font(.caption)
                    .textCase(nil)
            }
        }
    }

    private func serviceRow(_ service: any ManagedService) -> some View {
        let id = service.id.rawValue
        return Button { select([id]) } label: {
            HStack(spacing: 10) {
                Image(systemName: chosen.contains(id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(Color.accentColor)
                Text(verbatim: service.displayName).foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen.contains(id) ? .isSelected : [])
    }

    private func toggleAll() {
        let ids = services.map(\.id.rawValue)
        select(allChosen ? ids : ids.filter { !chosen.contains($0) })
    }
}

/// How much the chosen services hold, against free space
private struct BackupNowSizeSection: View {
    private static let largeBackupBytes: UInt64 = 10 * 1024 * 1024 * 1024

    let total: BackupEstimate?
    let isLoading: Bool

    var body: some View {
        if isLoading || total != nil {
            Section {
                if isLoading {
                    HStack {
                        Text("Checking the size on the server…")
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                } else if let total {
                    LabeledContent("Data to back up", value: Self.format(total.dataBytes))
                    LabeledContent("Free on the server", value: Self.format(total.freeBytes))
                }
            } footer: {
                if let total, !total.fitsOnDisk {
                    Text("The backup may not fit: it is larger than the free space on the server. A run that fills the disk takes the running services down with it.")
                } else if let total, total.dataBytes >= Self.largeBackupBytes {
                    Text("This is a large backup. It can take a long time and will use as much disk space again while it runs.")
                }
            }
        }
    }

    private static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .binary)
    }
}

/// Encryption, and whether the saved key or a new password
private struct BackupNowKeySection: View {
    @Binding var choice: BackupNowChoice
    let defaultsOn: Set<String>
    let alwaysEncrypted: Set<String>
    let alwaysEncryptedNames: [String]
    let hasStoredKey: Bool?

    private var needsKey: Bool { choice.needsKey(defaultsOn: defaultsOn, alwaysEncrypted: alwaysEncrypted) }

    var body: some View {
        Section {
            Toggle("Encrypt the backups", isOn: Binding(
                get: { choice.encrypting(defaultsOn: defaultsOn) },
                set: { choice.encrypt = $0 }))
            if needsKey {
                Picker("Key", selection: $choice.key) {
                    Text("Saved key").tag(BackupNowChoice.Key.stored)
                    Text("New password").tag(BackupNowChoice.Key.typed)
                }
                .pickerStyle(.segmented)
                if choice.key == .typed {
                    SecureField("Encryption password", text: $choice.passphrase)
                    SecureField("Repeat password", text: $choice.confirmation)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(alwaysEncryptedNames, id: \.self) { name in
                    Text(verbatim: UIL10n.string("%@ is always encrypted.", name))
                }
                if needsKey { Text(verbatim: keyNote) }
            }
        }
    }

    private var keyNote: String {
        switch choice.key {
        case .stored where hasStoredKey == false:
            return UIL10n.string("No key is saved on this server yet. Type a new password, or save one in Scheduled backups.")
        case .stored:
            return UIL10n.string("The key this server already uses for its backups. Old and new archives open with the same password.")
        case .typed:
            return UIL10n.string("A password typed here is used only for these backups and is never stored — without it the archives cannot be decrypted.")
        }
    }
}
