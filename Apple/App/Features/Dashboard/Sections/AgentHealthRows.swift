import AgentClient
import SwiftUI

/// Memory, connections, uptime and add-ons of the agent itself
struct AgentHealthRows: View {
    let health: Gryonixnexusd_V1_AgentHealth

    var body: some View {
        LabeledContent("Memory") { memoryValue }
        LabeledContent("Open connections") {
            Text(verbatim: "\(health.openChannels)").foregroundStyle(.secondary)
        }
        if let since = AgentHealthText.runningSince(health.startedAt) {
            LabeledContent("Running since") {
                Text(verbatim: since).foregroundStyle(.secondary)
            }
        }
        if !health.modules.isEmpty {
            AgentModulesList(modules: health.modules)
        }
    }

    private var memoryValue: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(verbatim: AgentHealthText.bytes(health.memoryBytes))
            Text(verbatim: UIL10n.string("peak %@", AgentHealthText.bytes(health.peakMemoryBytes)))
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}

/// The add-on programs beside the agent's core
private struct AgentModulesList: View {
    let modules: [Gryonixnexusd_V1_AgentModule]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Modules").font(.subheadline.weight(.semibold))
            ForEach(modules, id: \.name) { module in
                AgentModuleRow(module: module)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct AgentModuleRow: View {
    let module: Gryonixnexusd_V1_AgentModule

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(module.running ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(verbatim: module.name)
            Spacer(minLength: 8)
            Text(verbatim: "\(module.version) · \(AgentHealthText.bytes(module.sizeBytes))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
