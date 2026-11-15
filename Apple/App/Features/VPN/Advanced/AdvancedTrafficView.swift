import SwiftUI
import VPNProfile

/// Direct and proxied traffic, and the request log.
struct AdvancedTrafficView: View {
    @ObservedObject var model: AdvancedVPNModel
    @ObservedObject var tunnel: TunnelController

    var body: some View {
        Form {
            Section {
                Toggle("Count traffic and log requests", isOn: Binding(
                    get: { model.profile.collectsTraffic },
                    set: { value in model.update { $0.collectsTraffic = value } }))
            } footer: {
                Text("Off by default. The log lives in memory only and is gone when the tunnel stops. Apply again after changing this.")
            }
            if let traffic = model.traffic {
                Section("This session") {
                    row("Through the VPN", traffic.proxy)
                    row("Direct", traffic.direct)
                }
                Section("Recent requests") {
                    ForEach(traffic.requests.reversed()) { request in
                        HStack {
                            Text(verbatim: request.domain).lineLimit(1)
                            Spacer()
                            Text(verbatim: request.route).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Button("Update") { Task { await model.refreshTraffic(from: tunnel) } }
        }
        .formStyle(.grouped)
        .screenTitle("Traffic")
        .task { await model.refreshTraffic(from: tunnel) }
    }

    private func row(_ title: LocalizedStringKey, _ counter: AdvancedTraffic.Counter) -> some View {
        LabeledContent(title) {
            Text(ByteCountFormatter.string(fromByteCount: counter.total, countStyle: .file))
        }
    }
}
