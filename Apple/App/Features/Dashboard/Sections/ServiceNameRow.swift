import ServiceCatalog
import SwiftUI

/// The name a service shows on this server
struct ServiceNameRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    let service: any ManagedService

    var body: some View {
        PendingTextRow(id: "service-name-\(service.id.rawValue)", title: "Name", prompt: service.displayName,
                       saved: viewModel.title(of: service), edits: viewModel.rowEdits,
                       valid: { _ in true }) { name in
            let kept = name.trimmingCharacters(in: .whitespaces)
            await viewModel.renameService(service.id, to: kept == service.displayName ? "" : kept)
            return true
        }
    }
}
