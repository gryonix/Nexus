import ServerControl
import SwiftUI

struct MetricPanelEditor: View {
    let deployments: [Deployment]
    /// nil → adding
    let panel: MetricPanel?
    let onSave: (MetricPanel) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var deploymentID: UUID
    @State private var host: SSHHostID
    @State private var metrics: [HistoryMetric]
    @State private var range: HistoryRange

    init(deployments: [Deployment], panel: MetricPanel?,
         onSave: @escaping (MetricPanel) -> Void) {
        self.deployments = deployments
        self.panel = panel
        self.onSave = onSave
        _deploymentID = State(initialValue: panel?.deploymentID
                              ?? deployments.first?.id ?? UUID())
        _host = State(initialValue: panel?.host ?? .vps)
        _metrics = State(initialValue: panel?.metrics ?? [.cpu])
        _range = State(initialValue: panel?.range ?? .hour)
    }

    private var deployment: Deployment? {
        deployments.first { $0.id == deploymentID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    WrappingPicker("Server", selection: $deploymentID) {
                        ForEach(deployments) { deployment in
                            Text(verbatim: deployment.name).tag(deployment.id)
                        }
                    }
                    if let deployment, deployment.nodes.count > 1 {
                        Picker("Machine", selection: $host) {
                            ForEach(deployment.nodes) { node in
                                Text(machineName(node, in: deployment)).tag(node.sshHost)
                            }
                        }
                        .modifier(MachinePickerStyle(segmented: deployment.nodes.count <= 2))
                    }
                } header: {
                    Text("Server")
                }

                Section {
                    ForEach(MetricsPreferences.shared.offeredMetrics) { candidate in
                        Button {
                            toggle(candidate)
                        } label: {
                            HStack {
                                Label(candidate.title, systemImage: candidate.systemImage)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if metrics.contains(candidate) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                        .font(.body.weight(.semibold))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    WrappingPicker("Period", selection: $range) {
                        ForEach(MetricsPreferences.shared.offeredRanges) { range in
                            Text(range.title).tag(range)
                        }
                    }
                } header: {
                    InfoSectionHeader("What to show") {
                        Text("CPU, Memory and Disk can share one panel — they all read as a percentage. The others carry their own units, so picking one of them replaces the selection.")
                        Text("The period picks how far back the panel looks. The collector keeps a coarser sample the further back you go, so a year of history is one point per week.")
                    }
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle(panel == nil ? "Add panel" : "Edit panel")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(deployment == nil)
                }
            }
            .onChange(of: deploymentID) { _, _ in
                guard let deployment else { return }
                if !deployment.nodes.contains(where: { $0.sshHost == host }) {
                    host = deployment.nodes.first?.sshHost ?? .vps
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 380)
        #endif
    }

    private var ordered: [HistoryMetric] {
        HistoryMetric.allCases.filter { metrics.contains($0) }
    }

    /// Percent metrics accumulate; anything else is exclusive
    private func toggle(_ metric: HistoryMetric) {
        if metric.isPercent {
            var next = metrics.filter(\.isPercent)
            if let index = next.firstIndex(of: metric) { next.remove(at: index) } else { next.append(metric) }
            metrics = next.isEmpty ? [metric] : next
        } else {
            metrics = [metric]
        }
    }

    private struct MachinePickerStyle: ViewModifier {
        let segmented: Bool
        func body(content: Content) -> some View {
            if segmented {
                content.pickerStyle(.segmented)
            } else {
                content.pickerStyle(.menu)
            }
        }
    }

    /// What to call a machine in the picker
    private func machineName(_ node: DeploymentNode, in deployment: Deployment) -> String {
        deployment.metricsMachineLabel(for: node.sshHost) ?? node.endpoint.host
    }

    private func save() {
        guard let deployment else { return }
        var made = MetricPanel(deploymentID: deployment.id, host: host,
                               metrics: ordered, range: range)
        if let panel { made.id = panel.id }
        onSave(made)
        dismiss()
    }
}
