import ServerControl
import ServiceCatalog
import SwiftUI

/// USB drives that take a copy of each backup
struct BackupDrivesView: View {
    @StateObject private var model: BackupDrivesModel

    init(viewModel: DashboardViewModel) {
        _model = StateObject(wrappedValue: BackupDrivesModel(dashboard: viewModel))
    }

    var body: some View {
        Form {
            if model.state.supported {
                BackupDriveModeSection(model: model)
                BackupDrivePassphraseSection(model: model)
                BackupDriveListSection(model: model)
                BackupDriveLastCopySection(state: model.state)
            } else {
                Section {
                    Text("This server's backup tools are older than USB drives. Run Repair server on it first.")
                        .foregroundStyle(.secondary)
                }
            }
            if let error = model.error {
                Section { Text(verbatim: error).foregroundStyle(.red).font(.callout) }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .navigationTitle("USB drives")
        .raisedNavigationTitle()
        .refreshable { await model.load() }
        .task { await model.load() }
    }
}

/// Where archives go, and whether drive copies are encrypted
private struct BackupDriveModeSection: View {
    @ObservedObject var model: BackupDrivesModel

    var body: some View {
        Section {
            WrappingPicker("Archives go to", selection: binding(\.mode)) {
                Text("This server and the drives").tag(BackupDriveSettings.Mode.both)
                Text("The drives only").tag(BackupDriveSettings.Mode.drive)
                Text("This server only").tag(BackupDriveSettings.Mode.local)
            }
            Toggle("Encrypt copies on the drives", isOn: binding(\.encrypt))
        } header: {
            InfoSectionHeader("USB drives", note: "A drive plugged into this server gets a copy of every backup right after it is made. With several drives, each one gets its own copy. A missing or full drive never fails the backup; it is shown here instead.")
        } footer: {
            Text(footer)
        }
        .disabled(model.working != nil)
    }

    private var footer: LocalizedStringKey {
        switch model.state.settings.mode {
        case .both: return "Each archive stays on this server and is copied to every drive."
        case .drive: return "Each archive is moved to the drives. If no drive is plugged in, it stays on this server."
        case .local: return "The drives are left alone."
        }
    }

    private func binding<Value>(_ key: WritableKeyPath<BackupDriveSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.state.settings[keyPath: key] },
            set: { value in
                var settings = model.state.settings
                settings[keyPath: key] = value
                Task { await model.save(settings) }
            })
    }
}

/// Asks for a passphrase when encrypted copies lack one
private struct BackupDrivePassphraseSection: View {
    @ObservedObject var model: BackupDrivesModel
    @State private var passphrase = ""

    var body: some View {
        if model.state.settings.encrypt, !model.state.hasPassphrase {
            Section {
                SecureField(UIL10n.string("Backup passphrase"), text: $passphrase)
                    .textContentType(.password)
                Button("Save passphrase") {
                    let typed = passphrase
                    passphrase = ""
                    Task { await model.savePassphrase(typed) }
                }
                .rowActionButtonStyle()
                .disabled(passphrase.isEmpty || model.working != nil)
            } footer: {
                Text("Encrypted copies need a passphrase stored on the server. Keep it somewhere safe: without it a copy on the drive cannot be restored.")
            }
        }
    }
}

/// Every drive the server sees
private struct BackupDriveListSection: View {
    @ObservedObject var model: BackupDrivesModel

    var body: some View {
        Section {
            if model.drives.isEmpty {
                Text(model.isLoading ? "Looking for drives…" : "No USB drive is plugged in. Plug one into the server and pull to refresh.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.drives) { drive in
                NavigationLink {
                    BackupDriveDetailView(model: model, driveID: drive.id)
                } label: {
                    BackupDriveRow(drive: drive, used: model.isUsed(drive), status: model.status(of: drive))
                }
            }
        } header: {
            Text("Drives")
        }
    }
}

/// One drive: name, size, state
struct BackupDriveRow: View {
    let drive: BackupDrive
    let used: Bool
    let status: BackupDriveStatus?

    var body: some View {
        LabeledContent {
            Text(BackupDriveText.state(drive, used: used))
                .foregroundStyle(drive.state == .missing && used ? Color.orange : Color.secondary)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label { Text(verbatim: drive.name) } icon: { Image(systemName: "externaldrive") }
                Text(verbatim: BackupDriveText.size(drive, status: status))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// What the last copy to the drives did
private struct BackupDriveLastCopySection: View {
    let state: BackupDrivesState

    var body: some View {
        if let last = state.lastCopy {
            Section {
                LabeledContent("Last copy") {
                    Text(last, format: .relative(presentation: .named)).foregroundStyle(.secondary)
                }
                if !state.lastCopySucceeded {
                    Text(verbatim: state.lastError.isEmpty ? UIL10n.string("The last copy failed.") : state.lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

/// Words and numbers shown for a drive
enum BackupDriveText {
    static func state(_ drive: BackupDrive, used: Bool) -> String {
        switch drive.state {
        case .blank: return UIL10n.string("Not prepared")
        case .unmounted: return UIL10n.string("Not connected")
        case .missing: return UIL10n.string("Not plugged in")
        case .ready: return used ? UIL10n.string("In use") : UIL10n.string("Ready")
        }
    }

    static func size(_ drive: BackupDrive, status: BackupDriveStatus?) -> String {
        if let status, status.mounted, status.sizeBytes > 0 {
            return UIL10n.string("%@ free of %@", bytes(status.freeBytes), bytes(status.sizeBytes))
        }
        return drive.sizeBytes > 0 ? bytes(drive.sizeBytes) : "—"
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func speed(_ bytesPerSecond: Int64) -> String {
        UIL10n.string("%@/s", bytes(bytesPerSecond))
    }
}
