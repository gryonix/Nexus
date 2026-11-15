import SwiftUI

/// The Tailscale join key field
struct TailscaleKeySection: View {
    @ObservedObject var viewModel: ServiceConfigViewModel
    @State private var key = ""
    @FocusState private var focused: Bool

    var body: some View {
        Section {
            if viewModel.hasTailscaleKey {
                Label("Tailscale key added", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            SecureField(viewModel.hasTailscaleKey ? "Replace the key" : "Tailscale auth key",
                        text: $key)
                #if os(iOS) || os(tvOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .focused($focused)
                .accessibilityIdentifier("configurator.tailscaleKey")
                .onChange(of: key) { _, _ in Task { await save() } }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { key = "" }
                }
            Link("Open the Tailscale admin console",
                 destination: URL(string: "https://login.tailscale.com/admin/settings/keys")!)
        } header: {
            Text(verbatim: "Tailscale")
        } footer: {
            Text("This option needs an account at tailscale.com — Tailscale's service, not this app's. In its admin console, create an auth key (Settings → Keys) and paste it here. The key is stored securely on this device and sent to the server once.")
        }
        .task { viewModel.hasTailscaleKey = await TailscaleKeyStore.load() != nil }
    }

    private func save() async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await TailscaleKeyStore.save(trimmed)
        viewModel.hasTailscaleKey = true
    }
}
