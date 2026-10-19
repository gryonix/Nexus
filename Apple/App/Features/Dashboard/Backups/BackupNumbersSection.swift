import ServerControl
import SwiftUI

/// Counts and sizes of the backups across the fleet
struct BackupNumbersSection: View {
    @ObservedObject var model: ServerBackupsModel

    private var totals: BackupTotals { BackupOverview.totals(model.rows) }

    var body: some View {
        Section {
            if model.rows.isEmpty {
                emptyRow
            } else {
                summaryRows
            }
            BackupProblemRow(model: model)
        }
    }

    @ViewBuilder private var emptyRow: some View {
        if model.isLoading || !model.hasLoaded {
            HStack { Text("Loading…"); Spacer(); ProgressView().controlSize(.small) }
        } else {
            Text("No backups yet.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var summaryRows: some View {
        LabeledContent("Total size") { Text(Self.size(totals)).monospacedDigit() }
        LabeledContent(UIL10n.string("Backups: %lld", totals.count)) {
            if totals.onDrives > 0 {
                Text(UIL10n.string("Drives") + ": \(totals.onDrives)").foregroundStyle(.secondary)
            }
        }
        if let newest = totals.newest {
            LabeledContent("Last backup") {
                Text(newest.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    static func size(_ totals: BackupTotals) -> String {
        let text = ByteCountFormatter.string(fromByteCount: totals.bytes, countStyle: .file)
        return totals.unsized > 0 ? "≥ " + text : text
    }
}

/// Why this server gave no list
struct BackupProblemRow: View {
    @ObservedObject var model: ServerBackupsModel

    var body: some View {
        if let failure = model.failure {
            Label(failure, systemImage: HealthLevel.warning.systemImageName)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}
