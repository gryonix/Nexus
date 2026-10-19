import ServerControl
import SwiftUI

/// Per-host block (VPS or home server): WireGuard status, disk, memory
struct HostSection: View {
    let title: LocalizedStringKey
    var metrics: Loadable<HostMetricsSnapshot> = .idle
    let wireGuard: Loadable<WGStatus>?
    let disk: Loadable<[DiskMount]>
    let memory: Loadable<MemoryUsage>
    var history: MetricsHistoryTarget?
    var tourTarget: AppTourTarget?
    @AppStorage private var expanded: Bool
    /// Whether the history opens inline vs
    @AppStorage(MetricsDisplaySettings.historyInlineKey) private var historyInline = false
    @AppStorage(MetricsDisplaySettings.placementKey)
    private var placementRaw = MetricsPlacement.both.rawValue
    /// The non-root mounts, folded away by default — see `DiskRowPlan`
    @State private var otherDisksExpanded = false
    /// Whether this machine's metrics are drawn here at all
    private var showsMetrics: Bool {
        MetricsDisplaySettings.placement(from: placementRaw).showsInsideServer
    }

    init(title: LocalizedStringKey, storageKey: String,
         metrics: Loadable<HostMetricsSnapshot> = .idle,
         wireGuard: Loadable<WGStatus>?,
         disk: Loadable<[DiskMount]>,
         memory: Loadable<MemoryUsage>,
         history: MetricsHistoryTarget? = nil,
         tourTarget: AppTourTarget? = nil) {
        self.title = title
        self.metrics = metrics
        self.wireGuard = wireGuard
        self.disk = disk
        self.memory = memory
        self.history = history
        self.tourTarget = tourTarget
        _expanded = AppStorage(wrappedValue: false, "hostExpanded.\(storageKey)")
    }

    var body: some View {
        if showsMetrics || wireGuard != nil {
            section
        }
    }

    private var section: some View {
        Section {
            DisclosureGroup(isExpanded: Binding(
                get: { expanded },
                set: { newValue in withAnimation(.smooth(duration: 0.32)) { expanded = newValue } }
            )) {
                content
            } label: {
                header.modifier(TourTargetIf(tourTarget != nil, tourTarget ?? .serverMetrics))
            }
        }
    }

    private var header: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            if showsMetrics, case .loaded(let snapshot) = metrics, let cpu = snapshot.cpuPercent {
                Text(verbatim: "\(Int(cpu))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
            if showsMetrics { metricRows }
            wireGuardRow
    }

    @ViewBuilder
    private var metricRows: some View {
            switch metrics {
            case .loaded(let snapshot):
                HostMetricsHeaderRow(snapshot: snapshot, historyTarget: history)
            case .loading:
                HStack { Text("Metrics"); Spacer(); ProgressView().controlSize(.small) }
            case .failed(let message):
                Label(message, systemImage: HealthLevel.critical.systemImageName)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            case .idle:
                EmptyView()
            }

            memoryAndDiskRows
    }

    @ViewBuilder
    private var wireGuardRow: some View {
            switch wireGuard {
            case .loaded(let status):
                WGStatusView(status: status,
                            displayName: UIL10n.string("VPN connection"))
            case .loading:
                HStack { Text("VPN connection"); Spacer(); ProgressView().controlSize(.small) }
            case .failed(let message):
                Label(message, systemImage: HealthLevel.critical.systemImageName)
                    .font(.caption)
                    .foregroundStyle(.red)
            case .idle:
                Text("VPN connection: —").foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }
    }

    @ViewBuilder
    private var memoryAndDiskRows: some View {
            if let usage = memory.value {
                historyLink(.memory) {
                    UsageBarRow(title: "Memory",
                                usedBytes: usage.memUsedBytes,
                                totalBytes: usage.memTotalBytes)
                }
                if usage.swapTotalBytes > 0 {
                    // Swap has no dedicated history series — leave it plain.
                    UsageBarRow(title: "Swap",
                                usedBytes: usage.swapUsedBytes,
                                totalBytes: usage.swapTotalBytes)
                }
            } else if memory.isLoading {
                HStack { Text("Memory"); Spacer(); ProgressView().controlSize(.small) }
            }

            if let mounts = disk.value {
                diskRows(mounts)
            } else if disk.isLoading {
                HStack { Text("Disk"); Spacer(); ProgressView().controlSize(.small) }
            }

            if let history {
                if historyInline {
                    MetricsHistoryDisclosure(deployment: history.deployment, host: history.host)
                } else {
                    NavigationLink(value: history) {
                        Label("Metrics history", systemImage: "chart.xyaxis.line")
                    }
                }
                NavigationLink(value: EnergyTarget(deployment: history.deployment, host: history.host,
                                                   cores: metrics.value?.cpuCores)) {
                    Label("Energy", systemImage: "bolt")
                }
                NavigationLink(value: SpeedTestTarget(deployment: history.deployment, host: history.host)) {
                    Label("Speed test", systemImage: "speedometer")
                }
                NavigationLink(value: TopProcessesTarget(deployment: history.deployment, host: history.host)) {
                    Label("Top processes", systemImage: "list.number")
                }
            }
    }

    /// The disk block
    @ViewBuilder
    private func diskRows(_ mounts: [DiskMount]) -> some View {
        let plan = DiskRowPlan.make(mounts: mounts)
        ForEach(plan.primary, id: \.target) { mount in
            // Tap a usage row to open its history chart.
            historyLink(.disk) {
                UsageBarRow(title: plan.namesPrimaryByTarget ? "Disk \(mount.target)" : "Disk",
                            usedBytes: mount.usedBytes,
                            totalBytes: mount.sizeBytes)
            }
        }
        if !plan.others.isEmpty {
            DisclosureGroup(isExpanded: $otherDisksExpanded) {
                ForEach(plan.others, id: \.target) { mount in
                    UsageBarRow(title: LocalizedStringKey(mount.target),
                                usedBytes: mount.usedBytes,
                                totalBytes: mount.sizeBytes)
                }
            } label: {
                Text("Other volumes (\(plan.others.count))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func historyLink<Content: View>(_ metric: HistoryMetric,
                                            @ViewBuilder content: () -> Content) -> some View {
        if let history {
            NavigationLink(value: history.with(metric: metric)) { content() }
        } else {
            content()
        }
    }
}

/// Which host's history a HostSection links to
struct MetricsHistoryTarget: Hashable, Identifiable {
    let deployment: Deployment
    let host: SSHHostID
    /// Which metric the history screen opens on (deep-link); nil → CPU
    var metric: HistoryMetric?

    /// Identity for `navigationDestination(item:)`, which the server's panels section pushes with
    var id: String {
        "\(deployment.id)-\(String(describing: host))-\(metric?.rawValue ?? "cpu")"
    }

    /// Same host/target, opened straight to `metric`
    func with(metric: HistoryMetric) -> MetricsHistoryTarget {
        var copy = self
        copy.metric = metric
        return copy
    }
}

struct HostMetricsHeaderRow: View {
    let snapshot: HostMetricsSnapshot
    var historyTarget: MetricsHistoryTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let osPrettyName = snapshot.osPrettyName {
                HStack(spacing: 8) {
                    Text(osPrettyName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .revealsFullText(osPrettyName)
                    Spacer()
                    if let temperature = snapshot.temperatureCelsius {
                        Label(MetricsFormat.temperature(temperature),
                              systemImage: "thermometer.medium")
                            .font(.caption)
                            .foregroundStyle(temperature < 70 ? .green : .orange)
                    }
                }
            }

            cpuBlock
        }
        .padding(.vertical, 2)
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }

    @ViewBuilder
    private var cpuBlock: some View {
        let block = VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(verbatim: "CPU")
                    .font(.caption.weight(.medium))
                Text(verbatim: "\(snapshot.cpuCores) C")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: snapshot.cpuPercent.map { MetricsFormat.percent($0) } ?? "—")
                    .font(.caption)
                    .monospacedDigit()
            }
            SegmentedGaugeBar(fraction: (snapshot.cpuPercent ?? 0) / 100)
        }

        if let historyTarget {
            NavigationLink(value: historyTarget.with(metric: .cpu)) { block }
                .buttonStyle(.plain)
        } else {
            block
        }
    }
}
