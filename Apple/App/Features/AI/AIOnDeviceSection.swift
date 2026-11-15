import SwiftUI

/// Whether Apple's on-device model can answer here
struct AIOnDeviceSection: View {
    @State private var status = AIOnDevice.status

    var body: some View {
        Section {
            Label(title, systemImage: status == .ready ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(status == .ready ? Color.green : Color.orange)
        } footer: {
            Text("Questions and logs never leave this device. The model is small: good for explaining a command or an error, weaker on long logs, which are shortened to fit.")
        }
        .onAppear { status = AIOnDevice.status }
    }

    private var title: LocalizedStringKey {
        switch status {
        case .ready: "The on-device model is ready"
        case .deviceNotEligible: "This device does not support Apple Intelligence"
        case .intelligenceOff: "Turn on Apple Intelligence in Settings"
        case .downloading: "The model is still downloading; try again later"
        case .needsNewerSystem: "Needs iOS 26 or macOS 26"
        case .unavailable: "The on-device model is not available right now"
        }
    }
}
