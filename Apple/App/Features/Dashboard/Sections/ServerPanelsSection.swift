import ServerControl
import SwiftUI

struct ServerPanelsSection: View {
    let deployment: Deployment
    @Binding var adding: Bool
    @Binding var editing: MetricPanel?

    @StateObject private var model = MetricsDashboardViewModel()
    @Binding var history: MetricsHistoryTarget?

    /// Opens the arrangement screen for THIS server's panels
    @Binding var arranging: Bool

    init(deployment: Deployment, adding: Binding<Bool>, editing: Binding<MetricPanel?>,
         history: Binding<MetricsHistoryTarget?>, arranging: Binding<Bool>) {
        self.deployment = deployment
        _adding = adding
        _editing = editing
        _history = history
        _arranging = arranging
    }

    var body: some View {
        Section {
            ServerPanelsList(deployment: deployment, model: model, adding: $adding,
                             editing: $editing, history: $history, arranging: $arranging)
                .padding(16)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        } header: {
            InfoSectionHeader("My panels", note: "Panels you pin for this server: one metric, one machine, one period. They appear on the Metrics tab as well — that board is every server's panels together.")
        }
    }
}

private struct ServerPanelsList: View {
    let deployment: Deployment
    let model: MetricsDashboardViewModel
    @Binding var adding: Bool
    @Binding var editing: MetricPanel?
    @Binding var history: MetricsHistoryTarget?
    @Binding var arranging: Bool

    @ObservedObject private var store = MetricPanelStore.shared

    private var panels: [MetricPanel] {
        store.panels.filter { $0.deploymentID == deployment.id }
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(panels) { panel in
                PanelRow(panel: panel, deployment: deployment, model: model,
                         openHistory: { history = target(panel) },
                         onEdit: { editing = panel },
                         onDelete: { store.remove(panel) },
                         onMetrics: { metrics in
                             var updated = panel
                             updated.metricsRaw = metrics.map(\.rawValue)
                             store.replace(updated)
                         })
            }
            HStack {
                Button {
                    adding = true
                } label: {
                    Label("Add panel", systemImage: "plus.circle")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                if panels.count > 1 {
                    Button {
                        arranging = true
                    } label: {
                        Label("Arrange", systemImage: "arrow.up.arrow.down")
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .task(id: panels.map(\.id)) {
            model.update(panels: panels, deployments: [deployment])
        }
        .onDisappear { model.teardown() }
    }

    private func target(_ panel: MetricPanel) -> MetricsHistoryTarget {
        MetricsHistoryTarget(deployment: deployment, host: panel.host, metric: panel.metric)
    }
}

/// One tile, and the only view a reading invalidates
private struct PanelRow: View {
    let panel: MetricPanel
    let deployment: Deployment
    @ObservedObject var model: MetricsDashboardViewModel
    let openHistory: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMetrics: ([HistoryMetric]) -> Void

    var body: some View {
        MetricPanelCard(panel: panel,
                        deployment: deployment,
                        points: model.points[panel.source] ?? [],
                        errorMessage: model.errors[deployment.id],
                        openHistory: openHistory,
                        onEdit: onEdit,
                        onDelete: onDelete,
                        onMetrics: onMetrics)
            .equatable()
    }
}
