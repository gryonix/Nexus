import ServerControl
import ServiceCatalog
import SwiftUI

/// Edits when and what is backed up on a schedule
struct BackupScheduleView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @State private var draft = AutoBackupSettings()
    @State private var passphrase = ""
    @State private var isSaving = false

    private var needsPassphrase: Bool {
        draft.isOn && viewModel.services.contains {
            draft.services.contains($0.id.rawValue)
                && $0.actions(viewModel.deployment.serviceContext).backup.needsPassphrase
        }
    }

    private var canSave: Bool {
        guard !isSaving else { return false }
        // A schedule with no services would silently do nothing.
        if draft.isOn && draft.services.isEmpty { return false }
        // The passphrase is only mandatory when none is stored yet.
        if needsPassphrase && !viewModel.autoBackupHasPassphrase && passphrase.isEmpty {
            return false
        }
        return true
    }

    var body: some View {
        Form { content }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .navigationTitle("Scheduled backups")
        .raisedNavigationTitle()
        .task {
            await viewModel.loadAutoBackup()
            draft = viewModel.autoBackup
            applyToControls(draft.schedule)
        }
    }

    @State private var unit: Unit = .days
    @State private var interval = 1
    @State private var hour = 3
    @State private var minute = 0

    private enum Unit: Hashable { case hours, days }

    private var composedSchedule: CommandCatalog.Backups.Schedule {
        switch unit {
        case .hours: return .hours(count: interval, minute: minute)
        case .days: return .days(count: interval, hour: hour, minute: minute)
        }
    }

    @ViewBuilder
    private var content: some View {
        Toggle("Scheduled backups", isOn: Binding(
            get: { draft.schedule.isOn },
            set: { draft.schedule = $0 ? composedSchedule : .off }
        ))

        scheduleFields

        Button {
            save()
        } label: {
            if isSaving {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Saving…") }
            } else {
                Text("Save schedule")
            }
        }
        .rowActionButtonStyle()
        .disabled(!canSave)

        if let error = viewModel.autoBackupError {
            Label(error, systemImage: HealthLevel.critical.systemImageName)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var scheduleFields: some View {
        if draft.isOn {
            Picker("Repeat", selection: $unit) {
                Text("Hours").tag(Unit.hours)
                Text("Days").tag(Unit.days)
            }
            .pickerStyle(.segmented)
            .onChange(of: unit) { _, _ in
                interval = min(interval, unit == .hours ? 23 : 28)
                draft.schedule = composedSchedule
            }

            Stepper(value: $interval, in: 1...(unit == .hours ? 23 : 28)) {
                HStack {
                    Text(unit == .hours ? "Every N hours" : "Every N days")
                    Spacer()
                    Text(verbatim: "\(interval)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .onChange(of: interval) { _, _ in draft.schedule = composedSchedule }

            DatePicker(unit == .hours ? "At minute" : "At time",
                       selection: Binding(
                           get: { Self.date(hour: hour, minute: minute) },
                           set: { newValue in
                               let parts = Calendar.current.dateComponents([.hour, .minute],
                                                                            from: newValue)
                               hour = parts.hour ?? hour
                               minute = parts.minute ?? minute
                               draft.schedule = composedSchedule
                           }),
                       displayedComponents: .hourAndMinute)

            if unit == .hours {
                Text(UIL10n.string("Runs every %@ hours, at minute %@ past the hour.",
                                   "\(interval)", "\(minute)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Stepper(value: $draft.retention, in: 1...30) {
                HStack {
                    Text("Keep copies")
                    Spacer()
                    // verbatim: a bare number is not a translatable string.
                    Text(verbatim: "\(draft.retention)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            ForEach(backupCapableServices, id: \.id) { service in
                Toggle(service.displayName, isOn: binding(for: service.id))
            }

            if needsPassphrase {
                SecureField(viewModel.autoBackupHasPassphrase
                            ? UIL10n.string("New backup passphrase (optional)")
                            : UIL10n.string("Backup passphrase"),
                            text: $passphrase)
                    .textContentType(.password)
                Text(viewModel.autoBackupHasPassphrase
                     ? UIL10n.string("A passphrase is already stored on the server. Leave this empty to keep it.")
                     : UIL10n.string("Encrypted backups need this passphrase to run unattended. It is stored on the server, readable only by root, and you will need it to restore."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var backupCapableServices: [any ManagedService] {
        viewModel.services.filter {
            $0.actions(viewModel.deployment.serviceContext).backup != nil
        }
    }

    private func binding(for id: ServiceID) -> Binding<Bool> {
        Binding(
            get: { draft.services.contains(id.rawValue) },
            set: { isOn in
                if isOn { draft.services.insert(id.rawValue) }
                else { draft.services.remove(id.rawValue) }
            }
        )
    }

    private func save() {
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            await viewModel.saveAutoBackup(draft, passphrase: passphrase.isEmpty ? nil : passphrase)
            // Never keep the secret around after it has been sent.
            passphrase = ""
            draft = viewModel.autoBackup
            applyToControls(draft.schedule)
        }
    }

    /// Fills the pickers from a stored schedule
    private func applyToControls(_ schedule: CommandCatalog.Backups.Schedule) {
        switch schedule {
        case .off:
            break
        case .hours(let count, let atMinute):
            unit = .hours
            interval = count
            minute = atMinute
        case .days(let count, let atHour, let atMinute):
            unit = .days
            interval = count
            hour = atHour
            minute = atMinute
        }
    }

    private static func date(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }
}

private extension BackupSpec? {
    var needsPassphrase: Bool {
        if case .encryptedVolume = self { return true }
        return false
    }
}
