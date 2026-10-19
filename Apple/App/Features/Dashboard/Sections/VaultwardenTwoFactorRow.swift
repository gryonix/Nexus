import AgentControl
import ServerControl
import SwiftUI

/// Warns when a Vaultwarden account has no two-factor login
struct VaultwardenTwoFactorRow: View {
    let deployment: Deployment
    @State private var status: VaultwardenTwoFactorStatus?

    var body: some View {
        LabeledContent {
            summary
        } label: {
            Text("Two-factor login")
                .infoNote("Two-factor login",
                          "Turn it on in the web vault under Settings, Security, Two-step login.")
        }
        .task {
            if #available(macOS 15.0, *) {
                status = await VaultwardenTwoFactorProbe.read(deployment: deployment)
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        if let status {
            if status.needsAttention {
                Label("Users without two-factor login: \(status.usersWithoutTwoFactor) of \(status.users)",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.trailing)
            } else {
                Label("Every user has it", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }
}
