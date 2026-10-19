import ServerControl
import ServiceCatalog
import SwiftUI

/// One USB drive and the work it allows
struct BackupDriveDetailView: View {
    @ObservedObject var model: BackupDrivesModel
    let driveID: String

    private var drive: BackupDrive? { model.drives.first { $0.id == driveID } }

    var body: some View {
        Form {
            if let drive {
                BackupDriveFactsSection(drive: drive, status: model.status(of: drive))
                if drive.uuid != nil { BackupDriveUseSection(model: model, drive: drive) }
                if let check = model.checks[drive.id] { BackupDriveCheckSection(check: check) }
                BackupDriveActionsSection(model: model, drive: drive)
                if drive.disk != nil { BackupDriveFormatSection(model: model, drive: drive) }
            } else {
                Text("The drive is no longer on the list.").foregroundStyle(.secondary)
            }
            if let error = model.error {
                Section { Text(verbatim: error).foregroundStyle(.red).font(.callout) }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .navigationTitle(Text(verbatim: drive?.name ?? ""))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// Model, size, serial and state
private struct BackupDriveFactsSection: View {
    let drive: BackupDrive
    let status: BackupDriveStatus?

    var body: some View {
        Section {
            if let disk = drive.disk {
                LabeledContent("Model") { Text(verbatim: disk.model.isEmpty ? "—" : disk.model) }
                LabeledContent("Serial number") { Text(verbatim: disk.serial.isEmpty ? "—" : disk.serial) }
                LabeledContent("Path") { Text(verbatim: disk.path) }
            }
            LabeledContent("Size") { Text(verbatim: BackupDriveText.size(drive, status: status)) }
            LabeledContent("State") { Text(verbatim: BackupDriveText.state(drive, used: false)) }
        }
    }
}

/// Whether backups are copied to this drive
private struct BackupDriveUseSection: View {
    @ObservedObject var model: BackupDrivesModel
    let drive: BackupDrive

    var body: some View {
        Section {
            Toggle("Copy backups to this drive", isOn: Binding(
                get: { model.isUsed(drive) },
                set: { used in Task { await model.setUsed(drive, used) } }))
                .disabled(model.working != nil)
        }
    }
}

/// What the last check of this drive found
private struct BackupDriveCheckSection: View {
    let check: BackupDriveCheck

    var body: some View {
        Section {
            LabeledContent("Filesystem") { Text(filesystem) }
            LabeledContent("SMART") { Text(smart) }
            if check.writeBytesPerSecond > 0 {
                LabeledContent("Write speed") { Text(verbatim: BackupDriveText.speed(check.writeBytesPerSecond)) }
                LabeledContent("Read speed") { Text(verbatim: BackupDriveText.speed(check.readBytesPerSecond)) }
            }
        } header: {
            Text("Check")
        }
    }

    private var filesystem: LocalizedStringKey {
        switch check.filesystem {
        case .clean: return "No errors"
        case .errors: return "Errors found — format the drive"
        case .busy: return "Busy, not checked"
        case .unknown: return "Not checked"
        }
    }

    private var smart: LocalizedStringKey {
        switch check.smart {
        case .passed: return "Healthy"
        case .failed: return "Failing — replace the drive"
        case .none: return "Not reported (usual for USB sticks)"
        }
    }
}

/// Check, connect, unplug and forget
private struct BackupDriveActionsSection: View {
    @ObservedObject var model: BackupDrivesModel
    let drive: BackupDrive

    var body: some View {
        if drive.uuid != nil {
            Section {
                if drive.state != .missing { action("Check the drive", "stethoscope", .check) }
                if drive.state == .unmounted { action("Connect", "externaldrive.badge.plus", .attach) }
                if drive.state == .ready { action("Unplug safely", "eject", .eject) }
                action("Forget the drive", "externaldrive.badge.minus", .forget)
            } footer: {
                Text("A check only reads: the filesystem, SMART when the drive reports it, and a short speed test. Forgetting stops using the drive; the copies on it stay.")
            }
        }
    }

    private func action(_ title: LocalizedStringKey, _ symbol: String, _ work: StorageStep.DriveWork) -> some View {
        Button {
            Task { await model.perform(work, on: drive) }
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                if model.working == drive.id {
                    Spacer()
                    ProgressView().controlSize(.small)
                }
            }
        }
        .rowActionButtonStyle()
        .disabled(model.working != nil)
    }
}

/// Erases the drive and prepares it for backups
private struct BackupDriveFormatSection: View {
    @ObservedObject var model: BackupDrivesModel
    let drive: BackupDrive
    @State private var name = ""
    @State private var confirmation = ""

    private var expected: String {
        let model = drive.disk?.model ?? ""
        return model.isEmpty ? (drive.disk?.name ?? drive.name) : model
    }

    private var confirmed: Bool {
        confirmation.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(expected) == .orderedSame
    }

    var body: some View {
        Section {
            TextField(UIL10n.string("Drive name"), text: $name).autocorrectionDisabled()
            TextField(expected, text: $confirmation).autocorrectionDisabled()
            Button(role: .destructive) {
                Task { await model.format(drive, name: name) }
            } label: {
                Text("Format for backups")
            }
            .rowActionButtonStyle()
            .dangerTint()
            .disabled(!confirmed || !BackupDrives.isValidName(name) || model.working != nil)
        } header: {
            Text("Format")
        } footer: {
            Text("Everything on the drive is erased. Type \(expected) to confirm. The name is up to 11 lowercase letters, digits or dashes.")
        }
        .onAppear {
            if name.isEmpty {
                name = drive.state == .blank ? BackupDrives.suggestedName(taken: model.drives.map(\.name)) : drive.name
            }
        }
    }
}
