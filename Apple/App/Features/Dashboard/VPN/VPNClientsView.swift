import AgentControl
import ServerControl
import ServiceCatalog
import SwiftUI

struct VPNClientsView: View {
    @ObservedObject var viewModel: DashboardViewModel

    /// Which protocol is shown
    @State private var selection: ServiceID?

    init(viewModel: DashboardViewModel, initialProtocol: ServiceID? = nil) {
        self.viewModel = viewModel
        _selection = State(initialValue: initialProtocol)
    }

    var body: some View {
        CardList {
            ServerVPNSection(viewModel: viewModel, selection: $selection)
        }
        .navigationTitle("VPN devices")
        .raisedNavigationTitle()
        .refreshableWithShortcut {
            await viewModel.loadVPNClients(protocol: viewModel.vpnProtocol(preferring: selection))
        }
    }
}
