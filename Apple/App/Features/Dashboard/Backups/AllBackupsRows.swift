import ServerControl
import SwiftUI

struct BackupFilterSection: View {
    @ObservedObject var model: ServerBackupsModel
    @Binding var filter: BackupFilter

    private var services: [(id: String, name: String)] {
        var seen = Set<String>()
        return model.rows.compactMap { row in
            seen.insert(row.serviceID).inserted ? (row.serviceID, row.serviceName) : nil
        }
    }

    var body: some View {
        Section {
            Picker("Services", selection: $filter.serviceID) {
                Text("All services").tag(String?.none)
                ForEach(services, id: \.id) { service in
                    Text(verbatim: service.name).tag(String?.some(service.id))
                }
            }
            BackupPlacePicker(place: $filter.place)
        }
    }
}

/// One backup with its buttons, or a tick
struct BackupRow: View {
    let row: FleetBackup
    let canDelete: Bool
    let canShare: Bool
    var canRestore = false
    let isSharing: Bool
    /// Nil outside choosing mode
    let isSelected: Bool?
    let share: () -> Void
    let delete: () -> Void
    let toggle: () -> Void
    var restore: () -> Void = {}

    var body: some View {
        if let isSelected {
            Button(action: toggle) {
                HStack(spacing: 10) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(canDelete ? Color.accentColor : Color.secondary.opacity(0.4))
                    details
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canDelete)
        } else {
            HStack(spacing: 8) {
                details
                Spacer()
                actions
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.entry.displayName)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: row.serviceName)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(row.entry.sizeText) · \(dateText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let drive = row.entry.drive {
                Label(UIL10n.string("On the drive %@", drive), systemImage: "externaldrive")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateText: String {
        row.entry.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? row.entry.dateText
    }

    @ViewBuilder private var actions: some View {
        if canRestore {
            Button(action: restore) { Image(systemName: "clock.arrow.circlepath") }
                .glassIconButtonStyle()
                .accessibilityLabel(Text("Restore"))
        }
        if isSharing {
            ProgressView().controlSize(.small)
        } else if canShare {
            Button(action: share) { Image(systemName: "square.and.arrow.up") }
                .glassIconButtonStyle()
        }
        if canDelete {
            Button(role: .destructive, action: delete) { Image(systemName: "trash") }
                .dangerTint()
                .glassIconButtonStyle()
        }
    }
}

/// What can be done with the ticked backups
struct BackupSelectionSection: View {
    let selected: Int
    let shareable: Int
    let selectable: Int
    let isWorking: Bool
    let selectAll: () -> Void
    let share: () -> Void
    let delete: () -> Void

    var body: some View {
        Section {
            LabeledContent(UIL10n.string("%lld selected", selected)) {
                Button(selected == selectable ? "Deselect all" : "Select all", action: selectAll)
            }
            Button(action: share) {
                Label(UIL10n.string("Share (%lld)", shareable), systemImage: "square.and.arrow.up")
            }
            .rowActionButtonStyle()
            .disabled(shareable == 0 || isWorking)
            Button(role: .destructive, action: delete) {
                Label(UIL10n.string("Delete (%lld)", selected), systemImage: "trash")
            }
            .dangerTint()
            .rowActionButtonStyle()
            .disabled(selected == 0 || isWorking)
        }
    }
}

/// What a delete confirmation says, naming the drive when needed
enum BackupDeletionText {
    static func message(for entries: [BackupEntry]) -> String {
        if entries.count == 1, let entry = entries.first {
            guard let drive = entry.drive else {
                return UIL10n.string("%@ will be permanently deleted from the server.", entry.displayName)
            }
            return UIL10n.string("%@ will be permanently deleted from the drive %@.", entry.displayName, drive)
        }
        if entries.contains(where: { $0.drive != nil }) {
            return UIL10n.string("Selected backups: %lld, including copies on USB drives. They will be permanently deleted.",
                                 entries.count)
        }
        return UIL10n.string("Selected backups: %lld. They will be permanently deleted from the server.", entries.count)
    }
}
