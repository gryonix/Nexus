import AppIntents
import SwiftUI
import VPNTunnel
import WidgetKit

@available(iOS 18.0, macOS 26.0, *)
struct VPNControlWidget: ControlWidget {
    static let kind = "gryonixNexus.Control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetToggle(isOn: WidgetSnapshotReader.entry().value.tunnel.status.isActive,
                                action: ToggleTunnelIntent()) {
                Label { Text("VPN") } icon: { BrandMark.vpn }
            } valueLabel: { isOn in
                Text(isOn ? "Connected" : "Off")
            }
        }
        .displayName("VPN")
        .description("Turn this device's tunnel on or off.")
    }
}
