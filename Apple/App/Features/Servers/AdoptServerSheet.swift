import ServerControl
import ServiceCatalog
import SwiftUI

/// Progress + confirmation sheet for adopting an agent-managed server
@available(macOS 15.0, *)
struct AdoptServerSheet: View {
    let deployment: Deployment
    let deviceLabel: String
    let onAdopted: (AgentAdoption.Result) -> Void
    let onCancel: () -> Void

    @StateObject private var model = AdoptModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                switch model.phase {
                case .running(let stage):
                    runningView(stage)
                case .failure(let message):
                    failureView(message)
                case .success(let result):
                    successView(result)
                }
                Spacer(minLength: 0)

                #if os(macOS)
                macButtons
                #endif
            }
            .padding()
            .navigationTitle("Add via agent")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !model.isSuccess {
                        Button("Cancel", action: cancel)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if case .success(let result) = model.phase {
                        Button("Save") { confirm(result) }
                    }
                }
            }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
        #endif
        .task {
            await model.start(deployment: deployment, deviceLabel: deviceLabel)
        }
    }

    // MARK: Phases

    @ViewBuilder
    private func runningView(_ stage: AgentAdoption.Stage) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(stageText(stage)).font(.callout)
        }
    }

    /// Three failures, drawn as three
    @ViewBuilder
    private func failureView(_ failure: AgentAdoption.Failure) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch failure {
            case .keyRefused(let detail):
                Label("The server refused this device's key", systemImage: "key.slash")
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Nothing is known about the agent yet — the app did not get in. Close this, copy the command under “App SSH key” and run it on the server, then check again.")
                    .font(.callout)
            case .unreachable(let detail):
                Label("Could not reach the server", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Check the address, the port and that the machine is up.")
                    .font(.callout)
            case .noAgent(let detail):
                Label("No agent on this server", systemImage: "questionmark.circle")
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("You can still add it as a regular server and manage it over SSH.")
                    .font(.callout)
            case .agentFailed(let detail):
                Label("The agent answered, but the setup did not finish",
                      systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("The agent is there. You can add the server the ordinary way and try again from its own screen.")
                    .font(.callout)
            }
        }
    }

    @ViewBuilder
    private func successView(_ result: AgentAdoption.Result) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Agent connected", systemImage: "checkmark.circle")
                .font(.headline)
                .foregroundStyle(.green)
            if result.discoveredServices.isEmpty {
                Text("The agent found no installed services yet.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Found on this server:").font(.callout)
                ForEach(result.discoveredServices, id: \.id) { service in
                    HStack(spacing: 8) {
                        Image(systemName: "cube.box")
                            .foregroundStyle(.secondary)
                        Text(service.displayName.isEmpty ? service.id : service.displayName)
                        Spacer()
                        if result.installedOutside.contains(service.id) {
                            Text("not from this app")
                                .font(.caption).foregroundStyle(.orange)
                        } else if AgentServiceMapping.serviceIDs(forAgentIDs: [service.id]).isEmpty {
                            Text("untracked")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
                if !result.installedOutside.isEmpty {
                    Text("The ones marked «not from this app» were already on this server. gryonixNexus manages what it installed itself — to manage one of these from here, back its data up, remove it on the machine, and install it again from the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !result.notes.isEmpty {
                Divider()
                ForEach(result.notes, id: \.self) { note in
                    Label(note, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    #if os(macOS)
    @ViewBuilder
    private var macButtons: some View {
        HStack {
            Spacer()
            if case .success(let result) = model.phase {
                Button("Cancel", action: cancel)
                Button("Save") { confirm(result) }
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
    #endif

    // MARK: Actions

    private func confirm(_ result: AgentAdoption.Result) {
        onAdopted(result)
        dismiss()
    }

    private func cancel() {
        onCancel()
        dismiss()
    }

    private func stageText(_ stage: AgentAdoption.Stage) -> LocalizedStringKey {
        switch stage {
        case .connecting: return "Connecting to the agent…"
        case .pairing: return "Pairing this device…"
        case .discovering: return "Discovering services…"
        }
    }
}

@available(macOS 15.0, *)
@MainActor
private final class AdoptModel: ObservableObject {
    enum Phase {
        case running(AgentAdoption.Stage)
        case failure(AgentAdoption.Failure)
        case success(AgentAdoption.Result)
    }

    @Published var phase: Phase = .running(.connecting)

    var isSuccess: Bool { if case .success = phase { return true }; return false }

    private var started = false

    func start(deployment: Deployment, deviceLabel: String) async {
        guard !started else { return }
        started = true
        do {
            let result = try await AgentAdoption.adopt(
                deployment: deployment, deviceLabel: deviceLabel,
                onStage: { [weak self] stage in
                    await self?.show(stage)
                })
            phase = .success(result)
        } catch let failure as AgentAdoption.Failure {
            phase = .failure(failure)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failure(.agentFailed(message))
        }
    }

    private func show(_ stage: AgentAdoption.Stage) {
        phase = .running(stage)
    }
}
