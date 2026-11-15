import ServerControl
import ServiceCatalog
import SwiftUI

/// Changes the installed screen's name
struct AirPlayScreenRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onUpdate: (Deployment) -> Void
    @State private var name: String

    init(viewModel: DashboardViewModel, onUpdate: @escaping (Deployment) -> Void) {
        self.viewModel = viewModel
        self.onUpdate = onUpdate
        _name = State(initialValue: viewModel.deployment.serviceSettings.uxplayName)
    }

    var body: some View {
        AirPlayScreenFields(name: $name)
            .onChange(of: name) { offerEdit() }
    }

    /// Tells the bar whether the name waits
    private func offerEdit() {
        let field = $name
        let saved = viewModel.deployment.serviceSettings.uxplayName
        let edit = PendingRowEdits.Edit(
            id: "airplay-screen-name", text: .screen,
            apply: { [viewModel, onUpdate] in
                guard let updated = await viewModel.setAirPlayScreen(name: field.wrappedValue) else { return false }
                onUpdate(updated)
                return true
            },
            revert: { field.wrappedValue = saved })
        viewModel.rowEdits.offer(edit, changed: name != saved)
    }
}
