import ServerControl
import SwiftUI

/// Run a script on a chosen server
struct ScriptRunView: View {
    let script: SavedScript
    @Environment(\.dismiss) private var dismiss
    @State private var servers: [Deployment] = []
    @State private var pending: Pending?
    @State private var output: String?
    @State private var running = false

    private enum Mode { case terminal, output }
    private struct Pending: Identifiable {
        let server: Deployment
        let mode: Mode
        var id: String { "\(server.id)-\(mode)" }
    }

    var body: some View {
        NavigationStack {
            CardList {
                ForEach(servers.filter { script.appliesTo($0.id) }) { server in
                    Section(server.name) {
                        Button("Run in terminal") { pending = Pending(server: server, mode: .terminal) }
                        Button("Run and show output") { pending = Pending(server: server, mode: .output) }
                    }
                }
            }
            .screenTitle(Text(verbatim: script.name))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .overlay { if running { ProgressView() } }
            .sheet(item: $pending) { item in
                ScriptConfirmView(script: script, server: item.server) {
                    pending = nil
                    perform(item)
                }
            }
            .sheet(isPresented: Binding(get: { output != nil }, set: { if !$0 { output = nil } })) {
                outputSheet
            }
        }
        .task { servers = (try? FileDeploymentStore().load()) ?? [] }
    }

    private var outputSheet: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: output ?? "")
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .screenTitle("Output")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { output = nil } } }
        }
    }

    private func perform(_ item: Pending) {
        switch item.mode {
        case .terminal:
            sendToTerminal(on: item.server)
            dismiss()
        case .output:
            Task { await runForOutput(on: item.server) }
        }
    }

    private func sendToTerminal(on server: Deployment) {
        if #available(macOS 15.0, *),
           let live = TerminalSessions.shared.live.values.first(where: {
               $0.deployment.id == server.id && $0.state == .live
           }) {
            live.send(ArraySlice(Array(script.terminalInput.utf8)))
        } else {
            TerminalScriptQueue.shared.queue(script.terminalInput, for: server.id)
        }
        AppNavigator.shared.showServer(server.id, in: .terminal)
    }

    private func runForOutput(on server: Deployment) async {
        running = true
        defer { running = false }
        do {
            let runner = try await DashboardSessionFactory.makeRunnerDetached(deployment: server)
            let result = try await runner.run(script.execCommand, on: .vps, timeout: .seconds(60))
            let text = result.stdout + result.stderr
            output = text.isEmpty ? UIL10n.string("Finished with exit code %lld.", Int64(result.exitCode ?? -1)) : text
        } catch {
            output = error.localizedDescription
        }
    }
}

private struct ScriptConfirmView: View {
    let script: SavedScript
    let server: Deployment
    let onRun: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: script.body)
                    .font(.footnote.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .screenTitle(Text("Run on \(server.name)?"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Run") { onRun() } }
            }
        }
    }
}
