import ServerControl
import ServiceCatalog
import SwiftUI

/// Opens the backups hub
struct AutoBackupSection: View {
    @ObservedObject var viewModel: DashboardViewModel
    let requests: BackupRequests

    var body: some View {
        Section {
            NavigationLink {
                BackupsHubView(viewModel: viewModel, requests: requests)
            } label: {
                LabeledContent {
                    if viewModel.autoBackupAnswered {
                        Text(BackupScheduleSummary.text(viewModel.autoBackup.schedule))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Label("Backups", systemImage: "externaldrive.badge.timemachine")
                }
            }
        }
    }
}

/// What the hub can ask the server screen to open
struct BackupRequests {
    let backup: (ServiceID) -> Void
    let passphrase: (ServiceID) -> Void
    let restore: (ServiceID) -> Void
}

enum BackupScheduleSummary {
    static func text(_ schedule: CommandCatalog.Backups.Schedule) -> String {
        switch schedule {
        case .off:
            return UIL10n.string("Off")
        case .hours(let count, let minute):
            return UIL10n.string("Every %@ h", "\(count)") + String(format: " · :%02d", minute)
        case .days(let count, let hour, let minute):
            return UIL10n.string("Every %@ d", "\(count)") + String(format: " · %02d:%02d", hour, minute)
        }
    }
}
