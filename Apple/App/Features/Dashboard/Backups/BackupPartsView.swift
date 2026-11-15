import ServerControl
import ServiceCatalog
import SwiftUI

/// Which parts one kind of backup copies
struct BackupPartsView: View {
    typealias Scope = BackupPartScope

    @ObservedObject var viewModel: DashboardViewModel
    let scope: Scope

    var body: some View {
        Form {
            if viewModel.backupParts.supported {
                sharedSection
                ForEach(listed, id: \.self) { service in
                    serviceSection(service)
                }
            } else {
                Text("This server's backup scripts are older than this setting. Re-run the installation to update them.")
                    .foregroundStyle(.secondary)
            }
            if let error = viewModel.backupPartsError {
                Label(error, systemImage: HealthLevel.critical.systemImageName)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .bottomBarClearance()
        .screenTitle(scope == .regular ? "What to copy" : "Copy before updating")
        .raisedNavigationTitle()
        .task {
            await viewModel.loadBackupParts()
            if !viewModel.autoBackupAnswered { await viewModel.loadAutoBackup() }
        }
    }

    /// Services with backups turned on
    private var listed: [String] {
        viewModel.autoBackup.services.sorted { BackupPartText.service($0) < BackupPartText.service($1) }
    }

    private var sharedSection: some View {
        Section {
            ForEach(BackupPart.allCases, id: \.self) { part in
                Toggle(isOn: sharedBinding(part)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(BackupPartText.name(part))
                        Text(BackupPartText.detail(part)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Every service")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(scope == .regular
                     ? "Scheduled backups and the backup button copy these parts."
                     : "Before an update the server copies these parts. An update rarely touches your files, so they are left out by default: a second copy of a photo library needs as much free space again.")
                if !listed.isEmpty {
                    Text("A switch here changes every service below.")
                }
            }
        }
    }

    private func serviceSection(_ service: String) -> some View {
        Section(BackupPartText.service(service)) {
            ForEach(BackupPart.allCases, id: \.self) { part in
                Toggle(BackupPartText.name(part), isOn: serviceBinding(service, part))
            }
        }
    }

    private func sharedBinding(_ part: BackupPart) -> Binding<Bool> {
        Binding(
            get: { viewModel.backupParts.sharedIsOn(part, scope, among: listed) },
            set: { isOn in
                let change = viewModel.backupParts.settingShared(part, scope, on: isOn, among: listed)
                Task { await viewModel.saveBackupParts(change) }
            })
    }

    private func serviceBinding(_ service: String, _ part: BackupPart) -> Binding<Bool> {
        Binding(
            get: { viewModel.backupParts.choice(for: service)[scope].contains(part) },
            set: { isOn in
                let change = viewModel.backupParts.settingService(service, part, scope, on: isOn)
                Task { await viewModel.saveBackupParts(change) }
            })
    }
}

/// Names and descriptions of backup parts
enum BackupPartText {
    static func name(_ part: BackupPart) -> String {
        switch part {
        case .files: UIL10n.string("Files")
        case .settings: UIL10n.string("Settings")
        case .databases: UIL10n.string("Databases")
        }
    }

    static func detail(_ part: BackupPart) -> String {
        switch part {
        case .files: UIL10n.string("Photos, documents, mail and other files kept in the services.")
        case .settings: UIL10n.string("Service configuration and small state.")
        case .databases: UIL10n.string("Each service's database, dumped so it can be loaded back.")
        }
    }

    /// A service's name, or its id when unknown
    static func service(_ id: String) -> String {
        ServiceRegistry.service(ServiceID(rawValue: id))?.displayName ?? id
    }

    /// The chosen parts in one line
    static func summary(_ parts: Set<BackupPart>) -> String {
        let names = BackupPart.allCases.filter(parts.contains).map(name)
        return names.isEmpty ? UIL10n.string("Nothing") : names.joined(separator: ", ")
    }
}
