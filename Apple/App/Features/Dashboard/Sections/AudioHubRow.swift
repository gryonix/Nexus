import SwiftUI

/// Opens the hub's remote control
struct AudioHubRow: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        NavigationLink {
            AudioHubView(viewModel: viewModel)
        } label: {
            Label("Audio hub controls", systemImage: "slider.horizontal.3")
        }
    }
}
