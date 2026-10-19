#if os(iOS)
import SwiftUI
import VPNTunnel

/// The Lock Screen card settings, with a preview
struct VPNLockScreenSettingsView: View {
    @ObservedObject private var settings = LiveActivitySettings.shared

    var body: some View {
        Form {
            Section {
                preview
            } header: {
                Text("Preview")
            }
            Section {
                Toggle("Connection time", isOn: $settings.vpnIslandStyle.lockScreenStyle.showsTimer)
                Toggle("Server", isOn: $settings.vpnIslandStyle.lockScreenStyle.showsServer)
                Toggle("Protocol", isOn: $settings.vpnIslandStyle.lockScreenStyle.showsProtocol)
                Toggle("Traffic", isOn: $settings.vpnIslandStyle.lockScreenStyle.showsTraffic)
                Toggle("Stop button", isOn: $settings.vpnIslandStyle.lockScreenStyle.showsStopButton)
            } header: {
                Text("On the card")
            } footer: {
                Text("The colour is shared with the Dynamic Island.")
            }
            Section {
                Button("Reset to defaults") { settings.vpnIslandStyle.lockScreen = nil }
            }
        }
        .navigationTitle("Lock Screen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var preview: some View {
        VPNLockScreenCard(model: sampleModel) {
            IslandStopButton(isArmed: false, tint: sampleModel.tint) { face in face }
        }
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.black.opacity(0.85)))
        .environment(\.colorScheme, .dark)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
    }

    private var sampleModel: VPNIslandModel {
        VPNIslandModel(status: .connected(since: Date().addingTimeInterval(-754)),
                       statistics: TunnelStatistics(received: 48_300_000, sent: 3_100_000, lastHandshake: nil),
                       startedAt: Date().addingTimeInterval(-754),
                       serverName: "example.org",
                       protocolName: "WireGuard",
                       profileName: "iPhone",
                       isSimulated: false,
                       style: settings.vpnIslandStyle,
                       stopArmed: false)
    }
}
#endif
