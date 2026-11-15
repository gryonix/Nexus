import ServerControl
import SwiftUI

/// Removing a server, optionally taking the app's access back
struct ServerRemovalSheet: View {
    let deployment: Deployment
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var revokeAccess = true
    @State private var phase: ServerRemovalPhase = .choosing
    @State private var revoker: ServerAccessRevoker?

    var body: some View {
        NavigationStack {
            Form { content }
                .screenTitle("Remove this server from the app?")
                #if os(iOS) || os(tvOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }.disabled(phase == .working)
                    }
                }
        }
        .interactiveDismissDisabled(phase == .working)
    }

    /// Other devices share the key when iCloud carries it
    private var offersRevoke: Bool {
        !DemoServer.isDemo(deployment) && !CloudSync.shared.mode.includesKeys
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .choosing:
            ServerRemovalChoice(revokeAccess: $revokeAccess, offersRevoke: offersRevoke,
                                onRemove: start)
        case .working:
            Section { Label { Text("Removing the app's access…") } icon: { ProgressView() } }
        case .lastWayIn(let names, let lastIDs):
            ServerRemovalLastWayIn(names: names,
                                   keep: { finish(keeping: lastIDs) },
                                   removeAnyway: { finish(keeping: []) })
        case .unreachable(let message):
            ServerRemovalNote(text: UIL10n.string("The server did not answer: %@", message),
                              action: "Remove from the app only", onAction: complete)
        case .failed(let names):
            ServerRemovalNote(text: UIL10n.string("Some of it could not be removed from: %@. Remove it there by hand.",
                                                  names.joined(separator: ", ")),
                              action: "Done", onAction: complete)
        }
    }

    private func start() {
        guard revokeAccess, offersRevoke else { return complete() }
        phase = .working
        let revoker = ServerAccessRevoker(deployment: deployment)
        self.revoker = revoker
        Task {
            do {
                let checks = try await revoker.check()
                let last = checks.filter { $0.check?.isLastWayIn == true }
                if last.isEmpty {
                    finish(keeping: [])
                } else {
                    phase = .lastWayIn(last.map { revoker.displayName(of: $0.node) }, Set(last.map(\.id)))
                }
            } catch {
                phase = .unreachable(error.localizedDescription)
            }
        }
    }

    private func finish(keeping kept: Set<UUID>) {
        guard let revoker else { return complete() }
        phase = .working
        Task {
            let failures = await revoker.revoke(keepingKeyOn: kept)
            if failures.isEmpty { complete() } else { phase = .failed(failures) }
        }
    }

    private func complete() {
        onRemove()
        dismiss()
    }
}

/// Where the removal sheet stands
enum ServerRemovalPhase: Equatable {
    case choosing
    case working
    case lastWayIn([String], Set<UUID>)
    case unreachable(String)
    case failed([String])
}

/// The first step: what goes, and the remove button
private struct ServerRemovalChoice: View {
    @Binding var revokeAccess: Bool
    let offersRevoke: Bool
    let onRemove: () -> Void

    var body: some View {
        Section {
            Text("The server keeps running and its data is untouched — only the card, the app's SSH key and this server's pinned host keys are removed. To also clean up or wipe the machine, open the server and use “Erase server” at the bottom of its management screen.")
                .foregroundStyle(.secondary)
        }
        if offersRevoke {
            Section {
                Toggle("Also remove the app's access from the server", isOn: $revokeAccess)
            } footer: {
                Text("Signs in once more and removes this app's SSH key and this device's VPN connections from the server. If the key is the only way in, the app asks first.")
            }
        }
        Section {
            Button("Remove", role: .destructive, action: onRemove)
                .dangerTint()
        }
    }
}

/// Asks whether to keep the last key
private struct ServerRemovalLastWayIn: View {
    let names: [String]
    let keep: () -> Void
    let removeAnyway: () -> Void

    var body: some View {
        Section {
            Text(UIL10n.string("The app's key is the only way into %@. Without it nobody can sign in to this server any more.",
                               names.joined(separator: ", ")))
        }
        Section {
            Button("Keep the key on the server", action: keep)
            Button("Remove anyway", role: .destructive, action: removeAnyway)
                .dangerTint()
        }
    }
}

/// A short message and one way on
private struct ServerRemovalNote: View {
    let text: String
    let action: LocalizedStringKey
    let onAction: () -> Void

    var body: some View {
        Section { Text(text) }
        Section { Button(action, action: onAction) }
    }
}
