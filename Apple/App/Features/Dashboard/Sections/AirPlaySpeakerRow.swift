import ServerControl
import SwiftUI

/// Opens the installed speaker's settings
struct AirPlaySpeakerRow: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onUpdate: (Deployment) -> Void

    var body: some View {
        NavigationLink {
            AirPlaySpeakerSettingsView(viewModel: viewModel, onUpdate: onUpdate)
        } label: {
            Label("Speaker settings", systemImage: "slider.horizontal.3")
        }
    }
}
