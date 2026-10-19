import ServerControl
import SwiftUI

struct MetricsDashboardView: View {
    @StateObject private var store = MetricPanelStore.shared
    @StateObject private var servers = ServerListViewModel()

    @State private var adding = false
    @State private var editing: MetricPanel?
    @State private var path = NavigationPath()
    @State private var arranging = false
    @ObservedObject private var navigator = AppNavigator.shared

    private func openHistory(for deploymentID: UUID) {
        navigator.clearSectionServer(for: .metrics)
        if servers.deployments.isEmpty { servers.load() }
        guard let deployment = servers.deployments.first(where: { $0.id == deploymentID }) else { return }
        path.append(MetricsHistoryTarget(deployment: deployment, host: .vps))
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.panels.isEmpty {
                    emptyState
                } else {
                    MetricsBoardList(deployments: servers.deployments,
                                     path: $path, editing: $editing,
                                     reload: { servers.load() })
                }
            }
            .navigationTitle("Metrics")
            .sectionToolbar(.metrics, actions: {
                Button {
                    adding = true
                } label: {
                    Label("Add panel", systemImage: "plus")
                }
                .toolbarGlassButtonStyle()
                .disabled(servers.deployments.isEmpty)
            }, menu: {
                Button {
                    arranging = true
                } label: {
                    Label("Arrange panels", systemImage: "arrow.up.arrow.down")
                }
                .disabled(store.panels.count < 2)
            })
            .onReceive(navigator.$sectionServer.compactMap {
                $0?.tab == .metrics ? $0?.deploymentID : nil
            }) { openHistory(for: $0) }
            .task { if let id = navigator.sectionServer(for: .metrics) { openHistory(for: id) } }
            .onChange(of: servers.deployments) { _, deployments in
                store.seedDemoBoardIfEmpty(for: deployments)
            }
            .task { store.seedDemoBoardIfEmpty(for: servers.deployments) }
            .navigationDestination(for: MetricsHistoryTarget.self) { target in
                MetricsHistoryView(deployment: target.deployment, host: target.host,
                                   initialMetric: target.metric)
            }
            .navigationDestination(for: EnergyTarget.self) { target in
                EnergyView(target: target)
            }
            .navigationDestination(for: SpeedTestTarget.self) { target in
                SpeedTestView(target: target)
            }
            .navigationDestination(for: TopProcessesTarget.self) { target in
                TopProcessesView(target: target)
            }
            .sheet(isPresented: $adding) {
                MetricPanelEditor(deployments: servers.deployments, panel: nil) { panel in
                    store.add(panel)
                }
            }
            .sheet(item: $editing) { panel in
                MetricPanelEditor(deployments: servers.deployments, panel: panel) { updated in
                    store.replace(updated)
                }
            }
            .sheet(isPresented: $arranging) {
                MetricPanelReorderView(deployments: servers.deployments)
            }
            .task {
                servers.load()
                store.prune(against: servers.deployments)
                MetricsCache.shared.prune(keeping: Set(servers.deployments.map(\.id)))
            }
        }
        .popToRootOnReselect(.metrics) { path = NavigationPath() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No panels yet")
                .font(.title3.weight(.semibold))
            Text(servers.deployments.isEmpty
                 ? "Add a server first — panels are built from the servers this app already manages."
                 : "A panel is one server, one metric and one period. Add the few you actually watch and they all update side by side.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if !servers.deployments.isEmpty {
                Button {
                    adding = true
                } label: {
                    Text("Add panel").padding(.horizontal, 8)
                }
                .prominentActionButtonStyle()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The tiles themselves, and the only view a reading invalidates
private struct MetricsBoardList: View {
    let deployments: [Deployment]
    @Binding var path: NavigationPath
    @Binding var editing: MetricPanel?
    /// Re-reading the fleet on a pull
    let reload: () -> Void

    @StateObject private var model = MetricsDashboardViewModel()
    @ObservedObject private var store = MetricPanelStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(store.panels) { panel in
                    card(panel)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .bottomBarClearance()
        .background(listBackground)
        #if DEBUG && os(iOS)
        .background(HitTestProbe().frame(width: 0, height: 0))
        #endif
        .refreshableWithShortcut {
            reload()
            model.update(panels: store.panels, deployments: deployments)
            await model.reconnect()
        }
        .task { model.update(panels: store.panels, deployments: deployments) }
        .onChange(of: store.panels) { _, panels in
            model.update(panels: panels, deployments: deployments)
        }
        .onChange(of: deployments) { _, servers in
            model.update(panels: store.panels, deployments: servers)
        }
        .onDisappear { model.teardown() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: model.teardown()
            default: model.update(panels: store.panels, deployments: deployments)
            }
        }
    }

    /// One tile
    @ViewBuilder private func card(_ panel: MetricPanel) -> some View {
        if let deployment = deployments.first(where: { $0.id == panel.deploymentID }) {
            MetricPanelCard(panel: panel,
                            deployment: deployment,
                            points: model.points[panel.source] ?? [],
                            errorMessage: model.errors[deployment.id],
                            openHistory: {
                                path.append(MetricsHistoryTarget(
                                    deployment: deployment, host: panel.host,
                                    metric: panel.metric))
                            },
                            onEdit: { editing = panel },
                            onDelete: { store.remove(panel) },
                            onMetrics: { metrics in
                                var updated = panel
                                updated.metricsRaw = metrics.map(\.rawValue)
                                store.replace(updated)
                            })
            .equatable()
        }
    }

    private var listBackground: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #else
        Color.clear
        #endif
    }
}

struct MetricPanelCard: View, Equatable {
    static func == (lhs: MetricPanelCard, rhs: MetricPanelCard) -> Bool {
        lhs.panel == rhs.panel
            && lhs.deployment == rhs.deployment
            && lhs.errorMessage == rhs.errorMessage
            && (lhs.onEdit == nil) == (rhs.onEdit == nil)
            && (lhs.onDelete == nil) == (rhs.onDelete == nil)
            && (lhs.onMetrics == nil) == (rhs.onMetrics == nil)
            && lhs.points == rhs.points
    }

    let panel: MetricPanel
    let deployment: Deployment
    let points: [MetricsHistoryPoint]
    let errorMessage: String?
    let openHistory: () -> Void
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    /// Changing WHAT this tile plots, from the tile
    var onMetrics: (([HistoryMetric]) -> Void)?

    /// Whether this machine reports a temperature at all
    private var offersTemperature: Bool {
        points.contains { $0.temperatureCelsius != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            VStack(alignment: .leading, spacing: 8) {
                summary
                chart
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: openHistory)
        }
        .padding(14)
        .glassCardBackground(fallback: GlassPalette.cardBase, tint: deployment.displayTint)
        .background(
            RoundedRectangle(cornerRadius: GlassCardSurface.defaultCornerRadius,
                             style: .continuous)
                .fill(GlassPalette.cardBase)
        )
        .tint(deployment.displayTint)
    }

    private var header: some View {
        HStack(spacing: 8) {
            MetricBadge(metrics: panel.metrics,
                        offersTemperature: offersTemperature,
                        openHistory: openHistory,
                        onMetrics: onMetrics)
                .equatable()
            Spacer(minLength: 4)
            subtitle
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if onEdit != nil || onDelete != nil {
                PanelActionsButton(title: panel.metrics.map(\.plainTitle).joined(separator: " · "),
                                   subtitle: subtitleText,
                                   onEdit: onEdit, onDelete: onDelete)
            }
        }
    }

    private var subtitleText: String {
        var parts = [deployment.name]
        if let machine = deployment.metricsMachineLabel(for: panel.host) {
            parts.append(machine)
        }
        parts.append(panel.range.plainTitle)
        return parts.joined(separator: " · ")
    }

    private var subtitle: Text {
        var text = Text(verbatim: deployment.name)
        if let machine = deployment.metricsMachineLabel(for: panel.host) {
            text = text + Text(verbatim: " · ") + Text(verbatim: machine)
        }
        return text + Text(verbatim: " · ") + Text(panel.range.title)
    }

    @ViewBuilder
    private var summary: some View {
        if let errorMessage, points.isEmpty {
            Label(errorMessage, systemImage: "wifi.exclamationmark")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        } else if points.isEmpty {
            Text("Collecting…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(verbatim: MetricPanelSummary.text(metrics: panel.metrics,
                                                   range: panel.range,
                                                   points: points))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var chart: some View {
        if points.isEmpty {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(height: Self.chartHeight)
        } else {
            HistoryChart(points: points, metrics: panel.metrics, range: panel.range)
                .equatable()
                .frame(height: Self.chartHeight)
        }
    }

    private static let chartHeight: CGFloat = 140
}

private struct PanelActionsButton: View {
    let title: String
    let subtitle: String
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    @State private var showing = false

    #if DEBUG
    /// One sheet per run for the screenshot hook below
    nonisolated(unsafe) static var shown = false
    #endif

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) {
            MetricPanelActionsSheet(title: title, subtitle: subtitle,
                                    onEdit: { onEdit?() },
                                    onDelete: { onDelete?() })
        }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_PANEL_ACTIONS"] != nil,
               !PanelActionsButton.shown {
                PanelActionsButton.shown = true
                showing = true
            }
        }
        #endif
    }
}

private struct MetricBadge: View, Equatable {
    static func == (lhs: MetricBadge, rhs: MetricBadge) -> Bool {
        lhs.metrics == rhs.metrics
            && lhs.offersTemperature == rhs.offersTemperature
            && (lhs.onMetrics == nil) == (rhs.onMetrics == nil)
    }

    /// What the panel plots
    let metrics: [HistoryMetric]
    let offersTemperature: Bool
    let openHistory: () -> Void
    /// Changing what the tile plots
    var onMetrics: (([HistoryMetric]) -> Void)?

    @ObservedObject private var preferences = MetricsPreferences.shared

    @State private var choosing = false

    #if DEBUG
    /// One sheet per run for the screenshot hook above
    nonisolated(unsafe) static var pickerShown = false
    #endif

    private var offeredMetrics: [HistoryMetric] {
        preferences.offeredMetrics.filter { $0 != .temperature || offersTemperature }
    }

    var body: some View {
        Group {
            if onMetrics != nil {
                Button { choosing = true } label: { label(chevron: "chevron.up.chevron.down") }
                    .buttonStyle(.plain)
            } else {
                Button(action: openHistory) { label(chevron: "chevron.right") }
                    .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $choosing) {
            MetricChoiceSheet(offered: offeredMetrics, selected: metrics) { chosen in
                onMetrics?(chosen)
            }
        }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_OPEN_METRIC_PICKER"] != nil,
               onMetrics != nil, !MetricBadge.pickerShown {
                MetricBadge.pickerShown = true
                choosing = true
            }
        }
        #endif
    }

    private func label(chevron: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: metrics[0].systemImage)
                .foregroundStyle(metrics[0].tint)
            Text(metrics[0].title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if metrics.count > 1 {
                Text(verbatim: "+\(metrics.count - 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Image(systemName: chevron)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    MetricsDashboardView()
}
