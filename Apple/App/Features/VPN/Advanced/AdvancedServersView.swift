import SwiftUI
import VPNProfile

/// The imported servers, with delete.
struct AdvancedServersView: View {
    @ObservedObject var model: AdvancedVPNModel

    var body: some View {
        List {
            ForEach(model.profile.servers) { server in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: server.name)
                    Text(verbatim: "\(server.kind.rawValue) · \(server.host):\(server.port)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                let ids = Set(offsets.map { model.profile.servers[$0].id })
                model.update { $0 = $0.removing(serverIDs: ids) }
            }
        }
        .screenTitle("Servers")
        .overlay {
            if model.profile.servers.isEmpty { Text("No servers yet. Use Import.").foregroundStyle(.secondary) }
        }
    }
}
