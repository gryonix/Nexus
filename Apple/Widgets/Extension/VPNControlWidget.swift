import AppIntents
import SwiftUI
import VPNTunnel
import WidgetKit

@available(iOS 18.0, macOS 26.0, *)
struct VPNControlWidget: ControlWidget {
    static let kind = WidgetKinds.vpnControl

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            let status = WidgetSnapshotReader.entry().value.tunnel.status
            ControlWidgetToggle(isOn: status.isActive || status == .connecting,
                                action: ToggleTunnelIntent()) {
                Label { Text("VPN") } icon: { BrandMark.vpn }
            } valueLabel: { isOn in
                Text(status == .connecting ? "Connecting…" : isOn ? "Connected" : "Off")
            }
        }
        .displayName("VPN")
        .description("Turn this device's tunnel on or off.")
    }
}
