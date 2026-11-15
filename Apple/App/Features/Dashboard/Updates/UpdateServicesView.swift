import ServerControl
import ServiceCatalog
import SwiftUI

/// Every service with its update state and last run
struct UpdateServicesView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        Form {
            Section {
                ForEach(UpdateSummary.rowIDs(viewModel), id: \.self) { id in
                    UpdateStatusRow(viewModel: viewModel, id: id)
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .formRowButtons()
        #endif
        .bottomBarClearance()
        .screenTitle("All services")
        .raisedNavigationTitle()
        .refreshable { await viewModel.checkForUpdates() }
    }
}

/// One service: name, last run, and what the check found
struct UpdateStatusRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    let id: ServiceID

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: viewModel.title(of: id))
                if let record = viewModel.updateRunLog.records.last(where: { $0.service == id }) {
                    LastUpdateCaption(outcome: record.outcome)
                }
            }
            Spacer()
            status
        }
        .font(.callout)
    }

    @ViewBuilder private var status: some View {
        switch viewModel.updateReports[id] {
        case .available(let images):
            available(images)
        case .current:
            Text("Up to date").foregroundStyle(.secondary)
        case .selfManaged:
            Text("Updates itself").foregroundStyle(.secondary)
        case .rebuiltBySetup:
            Text("Moves with the app").foregroundStyle(.secondary)
        case .unknown:
            Text("Could not check").foregroundStyle(.orange)
        case nil:
            Text("Not checked").foregroundStyle(.secondary)
        }
    }

    private func available(_ images: [String]) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("Update available").foregroundStyle(.orange)
            Text(verbatim: images.joined(separator: ", "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            if let service = UpdateSummary.service(id, in: viewModel) {
                Button("Update now") {
                    Task { await viewModel.runUpdateNow(service) }
                }
                .rowActionButtonStyle()
                .font(.caption2)
            }
        }
    }
}

/// How the last update of a service ended
struct LastUpdateCaption: View {
    let outcome: ServiceUpdateRunRecord.Outcome

    var body: some View {
        Group {
            switch outcome {
            case .updated:
                Text("Last update: done").foregroundStyle(.secondary)
            case .rolledBack(let reason):
                Text("Last update rolled back: \(reason)").foregroundStyle(.orange)
            case .failed(let reason):
                Text("Last update failed: \(reason)").foregroundStyle(.orange)
            }
        }
        .font(.caption2)
        .lineLimit(2)
        .truncationMode(.middle)
    }
}
