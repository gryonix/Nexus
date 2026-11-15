import ServerControl
import ServiceCatalog
import SwiftUI

/// Changes the name a packaged speaker shows on phones
struct SpeakerNameRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    let service: any ManagedService
    let onUpdate: (Deployment) -> Void
    @State private var name: String

    init(viewModel: DashboardViewModel, service: any ManagedService, onUpdate: @escaping (Deployment) -> Void) {
        self.viewModel = viewModel
        self.service = service
        self.onUpdate = onUpdate
        _name = State(initialValue: viewModel.deployment.serviceSettings.speakerName)
    }

    var body: some View {
        TechnicalField(title: "Speaker name", prompt: viewModel.deployment.name, text: $name, spokenName: true)
            .onChange(of: name) { offerEdit() }
    }

    /// Tells the bar whether the name waits
    private func offerEdit() {
        let field = $name
        let saved = viewModel.deployment.serviceSettings.speakerName
        let edit = PendingRowEdits.Edit(
            id: "speaker-name-\(service.id.rawValue)", text: .speaker,
            apply: { [viewModel, service, onUpdate] in
                guard let updated = await viewModel.setSpeakerName(field.wrappedValue, reinstalling: service)
                else { return false }
                onUpdate(updated)
                return true
            },
            revert: { field.wrappedValue = saved })
        viewModel.rowEdits.offer(edit, changed: name != saved)
    }
}
