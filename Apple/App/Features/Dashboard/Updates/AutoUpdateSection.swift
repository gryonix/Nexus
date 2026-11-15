import ServerControl
import ServiceCatalog
import SwiftUI

/// Opens the updates hub
struct AutoUpdateSection: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        Section {
            NavigationLink {
                UpdatesHubView(viewModel: viewModel)
            } label: {
                LabeledContent {
                    Text(UpdateSummary.text(viewModel))
                        .font(.caption)
                        .foregroundStyle(UpdateSummary.waiting(viewModel) > 0 ? .orange : .secondary)
                } label: {
                    Label("Updates", systemImage: "arrow.down.circle")
                }
            }
            .accessibilityIdentifier("dashboard.updates")
        }
    }
}

/// What the updates row and hub say in one line
@MainActor
enum UpdateSummary {
    /// Services the server can update itself, by pulling images
    static func updatable(_ viewModel: DashboardViewModel) -> [any ManagedService] {
        viewModel.services.filter {
            $0.updateSpec(viewModel.deployment.serviceContext).flavour != .builtOnServer
        }
    }

    static func rowIDs(_ viewModel: DashboardViewModel) -> [ServiceID] {
        UpdateRows.statusRows(
            updatable: updatable(viewModel).map(\.id),
            deploymentServices: viewModel.deployment.services,
            reported: viewModel.updateReports.keys)
    }

    static func waiting(_ viewModel: DashboardViewModel) -> Int {
        rowIDs(viewModel).filter {
            if case .available = viewModel.updateReports[$0] { return true }
            return false
        }.count
    }

    static func current(_ viewModel: DashboardViewModel) -> Int {
        rowIDs(viewModel).filter { viewModel.updateReports[$0] == .current }.count
    }

    static func text(_ viewModel: DashboardViewModel) -> String {
        let count = waiting(viewModel)
        return count > 0 ? UIL10n.string("%@ waiting", "\(count)") : ""
    }

    static func service(_ id: ServiceID, in viewModel: DashboardViewModel) -> (any ManagedService)? {
        viewModel.services.first { $0.id == id } ?? ServiceRegistry.service(id)
    }
}
