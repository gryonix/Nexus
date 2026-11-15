import Combine
import ServerControl
import SwiftUI

/// Saved port forwards of one server
struct PortForwardsView: View {
    let deployment: Deployment
    @ObservedObject private var manager = PortForwardManager.shared
    @State private var editing: PortForward?
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        CardList {
            Section {
                let list = manager.forwards(for: deployment)
                if list.isEmpty { Text("No port forwards yet.").foregroundStyle(.secondary) }
                ForEach(list) { forward in row(forward) }
            } footer: {
                #if os(iOS)
                Text("Forwards stay open only while the app is in the foreground. Opening the local port reaches the remote host as the server sees it.")
                #else
                Text("Opening the local port reaches the remote host as the server sees it.")
                #endif
            }
        }
        .screenTitle("Port forwarding")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = PortForward(deploymentID: deployment.id, localPort: 8080, remotePort: 80)
                } label: { Label("Add forward", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { forward in
            PortForwardEditor(forward: forward, existing: manager.forwards) { manager.save($0) }
        }
        .onReceive(tick) { _ in manager.refreshCounts() }
    }

    private func row(_ forward: PortForward) -> some View {
        let state = manager.state(of: forward)
        return HStack {
            Button { editing = forward } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(forward.title)
                    Text(forward.summary).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(statusText(state)).font(.caption).foregroundStyle(statusColor(state))
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button(state.isActive ? "Stop" : "Start") {
                if state.isActive { manager.stop(forward) }
                else { Task { await manager.start(forward, on: deployment) } }
            }
            .secondaryActionButtonStyle()
        }
        .swipeActions { Button("Delete", role: .destructive) { manager.delete(forward) }.dangerTint() }
    }

    private func statusText(_ state: PortForwardState) -> String {
        switch state {
        case .stopped: return UIL10n.string("Stopped")
        case .starting: return UIL10n.string("Starting…")
        case .running(let count): return UIL10n.string("Running, %lld connection(s)", Int64(count))
        case .failed(let message): return message
        }
    }

    private func statusColor(_ state: PortForwardState) -> Color {
        switch state {
        case .running: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
}

private struct PortForwardEditor: View {
    @State var forward: PortForward
    let existing: [PortForward]
    let onSave: (PortForward) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CardList {
                Section {
                    TextField("Name (optional)", text: $forward.name)
                    portField("Local port", value: $forward.localPort)
                    TextField("Remote host", text: $forward.remoteHost)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    portField("Remote port", value: $forward.remotePort)
                } footer: {
                    Text(problemText)
                }
            }
            .screenTitle("Port forward")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(forward); dismiss() }
                        .disabled(!forward.problems(among: existing).isEmpty)
                }
            }
        }
    }

    private func portField(_ title: LocalizedStringKey, value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", value: value, format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
        }
    }

    private var problemText: String {
        let problems = forward.problems(among: existing)
        if problems.contains(.localPort) { return UIL10n.string("The local port must be between 1024 and 65535.") }
        if problems.contains(.duplicateLocalPort) { return UIL10n.string("Another forward already uses this local port.") }
        if problems.contains(.remoteHost) { return UIL10n.string("Enter the remote host.") }
        if problems.contains(.remotePort) { return UIL10n.string("The remote port must be between 1 and 65535.") }
        return ""
    }
}
