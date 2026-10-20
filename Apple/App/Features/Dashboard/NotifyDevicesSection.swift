import AgentClient
import SwiftUI

/// The devices that get this server's notifications
struct NotifyDevicesSection: View {
    let devices: [Gryonixnexusd_V1_NotifyDevice]
    let thisToken: String?
    let onRemove: (Gryonixnexusd_V1_NotifyDevice) -> Void

    var body: some View {
        if !devices.isEmpty {
            Section {
                ForEach(devices, id: \.token) { device in
                    row(device)
                }
            } header: {
                Text("Devices")
            } footer: {
                Text("A removed device no longer gets this server's notifications.")
            }
        }
    }

    private func row(_ device: Gryonixnexusd_V1_NotifyDevice) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: Self.name(of: device))
                details(device).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Remove", role: .destructive) { onRemove(device) }
                .buttonStyle(.borderless)
                .dangerTint()
        }
    }

    @ViewBuilder private func details(_ device: Gryonixnexusd_V1_NotifyDevice) -> some View {
        if device.token == thisToken {
            Text("This device")
        } else if device.addedAt > 0 {
            Text(Date(timeIntervalSince1970: TimeInterval(device.addedAt)), style: .date)
        } else if !device.appVersion.isEmpty {
            Text(verbatim: device.appVersion)
        }
    }

    static func name(of device: Gryonixnexusd_V1_NotifyDevice) -> String {
        if !device.name.isEmpty { return device.name }
        return device.platform == "fcm" ? "Android" : "Apple"
    }
}
