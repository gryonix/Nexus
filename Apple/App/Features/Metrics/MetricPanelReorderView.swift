import ServerControl
import SwiftUI

/// Drag-to-reorder for metric panels, on its own screen
struct MetricPanelReorderView: View {
    var deploymentID: UUID?
    let deployments: [Deployment]

    @ObservedObject private var store = MetricPanelStore.shared
    @Environment(\.dismiss) private var dismiss

    private var panels: [MetricPanel] {
        guard let deploymentID else { return store.panels }
        return store.panels.filter { $0.deploymentID == deploymentID }
    }

    var body: some View {
        NavigationStack {
            ReorderableList(phone: .form) {
                Section {
                    ForEach(panels) { panel in
                        row(panel)
                    }
                    .onMove(perform: move)
                    .onDelete(perform: delete)
                } header: {
                    InfoSectionHeader("Panels", note: "Drag to reorder. This is the order the panels appear in, and swiping one away removes it.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Arrange panels")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: panels.isEmpty) { _, empty in
                if empty { dismiss() }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 320)
        #endif
    }

    private func row(_ panel: MetricPanel) -> some View {
        HStack(spacing: 12) {
            Image(systemName: panel.metric.systemImage)
                .foregroundStyle(panel.metric.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                title(panel)
                subtitle(panel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func title(_ panel: MetricPanel) -> Text {
        let name = Text(panel.metric.title)
        guard panel.metrics.count > 1 else { return name }
        return name + Text(verbatim: " +\(panel.metrics.count - 1)")
    }

    /// Which machine and over how long
    private func subtitle(_ panel: MetricPanel) -> Text {
        let deployment = deployments.first { $0.id == panel.deploymentID }
        var text = Text(verbatim: "")
        if deploymentID == nil, let deployment {
            text = Text(verbatim: deployment.name) + Text(verbatim: " · ")
        }
        if let machine = deployment?.metricsMachineLabel(for: panel.host) {
            text = text + Text(verbatim: machine) + Text(verbatim: " · ")
        }
        return text + Text(panel.range.title)
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        var updated = panels
        updated.move(fromOffsets: offsets, toOffset: destination)
        store.reorder(updated)
    }

    private func delete(at offsets: IndexSet) {
        let doomed = panels
        for index in offsets where doomed.indices.contains(index) {
            store.remove(doomed[index])
        }
    }
}
