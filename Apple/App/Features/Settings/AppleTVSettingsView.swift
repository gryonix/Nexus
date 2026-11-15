#if os(iOS)
import ServerControl
import SwiftUI
import TVLink

/// Settings › Apple TV: pair, confirm the license, send servers
struct AppleTVSettingsView: View {
    @ObservedObject private var link = AppleTVLink.shared
    @State private var pairing: PendingTVPairing?
    @State private var sendingTo: TVPairedTV?
    @State private var message: String?

    var body: some View {
        Form {
            pairedSection
            nearbySection
        }
        .screenTitle("Apple TV")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { link.startBrowsing() }
        .onDisappear { link.stopBrowsing() }
        .task { await link.vouchAll() }
        .sheet(item: $pairing) { PairTVSheet(pending: $0) }
        .sheet(item: $sendingTo) { SendServersToTVSheet(tv: $0) }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    private var pairedSection: some View {
        Section {
            ForEach(link.paired) { tv in
                PairedTVRow(tv: tv, onSend: { sendingTo = tv }, onForget: { Task { await link.forget(tv) } })
            }
            if !link.paired.isEmpty {
                Button("Confirm the license now") { Task { await link.confirmNow() } }
            }
        } header: {
            Text("Paired")
        } footer: {
            Text("Nexus confirms your license on a paired Apple TV by itself whenever it is open on the same network. Without that, the Apple TV stays unlocked for 10 days, or 20 with a lifetime license.")
        }
    }

    private var nearbySection: some View {
        Section {
            if link.unpaired.isEmpty {
                Label("Looking for Apple TVs with Nexus…", systemImage: "appletv")
                    .foregroundStyle(.secondary)
            }
            ForEach(link.unpaired) { tv in
                Button {
                    Task { await begin(tv) }
                } label: {
                    Label(tv.name, systemImage: "appletv")
                }
            }
        } header: {
            Text("On this network")
        } footer: {
            Text("Open Nexus on the Apple TV. It shows a code to type here.")
        }
    }

    private func begin(_ tv: TVNearby) async {
        do {
            pairing = PendingTVPairing(name: tv.name, attempt: try await link.beginPairing(tv))
        } catch {
            message = error.localizedDescription
        }
    }
}

/// A pairing waiting for the code the TV shows
struct PendingTVPairing: Identifiable {
    let id = UUID()
    let name: String
    let attempt: TVPairingAttempt
}

private struct PairedTVRow: View {
    let tv: TVPairedTV
    let onSend: () -> Void
    let onForget: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(tv.name, systemImage: "appletv.fill")
            if let vouched = tv.vouchedAt {
                Text("License confirmed \(vouched.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Send servers…", action: onSend)
                Spacer()
                Button("Forget", role: .destructive, action: onForget)
                .dangerTint()
            }
            .buttonStyle(.borderless)
        }
    }
}

/// Typing the TV's six digits
private struct PairTVSheet: View {
    let pending: PendingTVPairing
    @Environment(\.dismiss) private var dismiss
    @State private var digits = ""
    @State private var working = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("123 456", text: $digits)
                        .keyboardType(.numberPad)
                        .font(.title2.monospacedDigit())
                } footer: {
                    Text(failure ?? UIL10n.string("Type the code shown on “%@”.", pending.name))
                        .foregroundStyle(failure == nil ? Color.secondary : Color.red)
                }
            }
            .screenTitle("Pair Apple TV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { Task { await pending.attempt.cancel() }; dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pair") { Task { await pair() } }
                        .disabled(TVPairingCode(digits) == nil || working)
                }
            }
        }
    }

    private func pair() async {
        guard let code = TVPairingCode(digits) else { return }
        working = true
        do {
            try await AppleTVLink.shared.finishPairing(pending.attempt, code: code)
            dismiss()
        } catch TVHandshakeError.codeMismatch, TVHandshakeError.refused(.wrongCode) {
            failure = UIL10n.string("The code did not match. Try again from the list: the Apple TV shows a new code.")
            working = false
        } catch {
            failure = UIL10n.string("The Apple TV stopped answering. Choose it in the list again.")
            working = false
        }
    }
}

/// Picks servers and sends them, keys included, to one TV
private struct SendServersToTVSheet: View {
    let tv: TVPairedTV
    @Environment(\.dismiss) private var dismiss
    @State private var deployments: [Deployment] = []
    @State private var chosen: Set<UUID> = []
    @State private var working = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List(deployments, selection: $chosen) { deployment in
                Text(verbatim: deployment.name).tag(deployment.id)
            }
            .environment(\.editMode, .constant(.active))
            .safeAreaInset(edge: .bottom) {
                if let failure { Text(verbatim: failure).foregroundStyle(.red).padding() }
            }
            .screenTitle(tv.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { Task { await send() } }.disabled(chosen.isEmpty || working)
                }
            }
            .task {
                deployments = ((try? FileDeploymentStore().load()) ?? []).filter { !DemoServer.isDemo($0) }
            }
        }
    }

    private func send() async {
        working = true
        do {
            try await AppleTVLink.shared.send(deployments.filter { chosen.contains($0.id) }, to: tv)
            dismiss()
        } catch {
            failure = error.localizedDescription
            working = false
        }
    }
}
#endif
