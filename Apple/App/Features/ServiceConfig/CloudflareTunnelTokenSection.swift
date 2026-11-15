import SwiftUI

/// Shows whether a Cloudflare tunnel token is saved
struct CloudflareTunnelTokenSection: View {
    @State private var hasToken: Bool?

    var body: some View {
        Section {
            if hasToken == true {
                Label("Cloudflare token added", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if hasToken == false {
                NavigationLink {
                    DNSAPISettingsView().licenseLocked()
                } label: {
                    Label("Add a Cloudflare token", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                .accessibilityIdentifier("configurator.cloudflareToken")
            }
        } header: {
            Text(verbatim: "Cloudflare")
        } footer: {
            Text("The domain must be on your Cloudflare account. The app creates the tunnel and its DNS names there with a token that has Account · Cloudflare Tunnel · Edit.")
        }
        .onAppear { Task { await reload() } }
    }

    private func reload() async {
        hasToken = await DNSCredentialTokenStore.currentCloudflareTunnelToken() != nil
    }
}
