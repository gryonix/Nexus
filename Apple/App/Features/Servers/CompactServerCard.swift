import ServerControl
import ServiceCatalog
import SwiftUI

struct CompactServerCard: View, Equatable {
    let deployment: Deployment
    let host: SSHHostID
    let state: ServerHostMetricsState
    var embedded = false

    @AppStorage(MetricsDisplaySettings.indicatorStyleKey)
    private var indicatorStyleRaw = MetricsIndicatorStyle.bars.rawValue

    /// Only a reading that is still true — see `liveSnapshot`
    private var snapshot: HostMetricsSnapshot? { state.liveSnapshot }
    private var indicatorStyle: MetricsIndicatorStyle {
        deployment.metricsIndicatorStyle
            ?? MetricsDisplaySettings.indicatorStyle(from: indicatorStyleRaw)
    }

    var body: some View {
        if embedded {
            content
        } else {
            content
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .glassCardBackground(fallback: GlassPalette.cardBase, tint: deployment.displayTint)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            if state.errorMessage != nil {
                ServerOfflineNote(deployment: deployment, host: host, lastSeen: state.lastSeen,
                                  offlineSince: state.offlineSince, compact: true)
                    .frame(minHeight: metricsBlockHeight)
            } else {
                gauges
                    .layoutPriority(1)
                Spacer(minLength: 0)
                traffic
            }
        }
        .tint(deployment.displayTint)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            if embedded {
                hostBadge
            } else {
                leadingBadge
                Text(deployment.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
                if deployment.isMultiHost { hostBadge }
            }
            Spacer(minLength: 4)
            headerStatus
        }
    }

    @ViewBuilder
    private var leadingBadge: some View {
        if let symbol = deployment.iconSymbol {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 20, height: 20)
        } else {
            OSBadge(osID: snapshot?.osID, isMultiHost: deployment.isMultiHost)
        }
    }

    private var hostBadge: some View {
        Text(HostBadgeTitle.of(host, in: deployment))
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(.tint)
    }

    @ViewBuilder
    private var headerStatus: some View {
        if let snapshot {
            HStack(spacing: 4) {
                if state.errorMessage != nil {
                    // Stale: the last reading stays up, marked unreachable.
                    Image(systemName: "wifi.exclamationmark")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if !snapshot.isPartial {
                    Text(verbatim: MetricsFormat.uptime(snapshot.uptimeSeconds))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize()
        } else if state.errorMessage != nil {
            Image(systemName: "wifi.exclamationmark")
                .font(.caption2)
                .foregroundStyle(.red)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    // MARK: - Gauges

    private var gauges: some View {
        indicator
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: metricsBlockHeight, maxHeight: .infinity)
    }

    @ScaledMetric(relativeTo: .caption2) private var metricsBlockHeight = MetricBlock.compact

    @ViewBuilder
    private var indicator: some View {
        switch indicatorStyle {
        case .bars: linearGauges(track: false)
        case .track: linearGauges(track: true)
        case .rings: ringGauges
        case .minimal: minimalGauges
        }
    }

    private func linearGauges(track: Bool) -> some View {
        spread(minGap: MetricBlock.compactGap, maxGap: MetricBlock.compactGapMax) { metric in
            CompactGaugeRow(label: metric.label, percent: metric.percent,
                            fraction: metric.fraction, track: track)
        }
    }

    private var ringGauges: some View {
        GeometryReader { geo in
            let stacked = RingLayout.stacks(in: geo.size, count: 3,
                                            gutter: RingLayout.compactGutter,
                                            stackedGutter: RingLayout.stackedGutter,
                                            labelHeight: ringLabelHeight,
                                            labelWidth: ringLabelWidth, floor: 20,
                                            cap: RingLayout.compactMaxDiameter)
            let diameter = ringDiameter(in: geo.size, stacked: stacked)
            let rings = ForEach(MetricDatum.all(for: snapshot)) { metric in
                RingGauge(label: metric.label, fraction: metric.fraction,
                          diameter: diameter,
                          labelPlacement: stacked ? .trailing : .below)
                    .frame(maxWidth: .infinity, maxHeight: stacked ? .infinity : nil,
                           alignment: stacked ? .leading : .center)
            }
            Group {
                if stacked {
                    VStack(spacing: RingLayout.stackedGutter) { rings }
                } else {
                    HStack(spacing: 0) { rings }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ScaledMetric(relativeTo: .caption2) private var ringLabelHeight = RingLayout.labelHeight

    @ScaledMetric(relativeTo: .subheadline) private var ringLabelWidth = RingLayout.trailingLabelWidth

    private func ringDiameter(in size: CGSize, stacked: Bool) -> CGFloat {
        stacked
            ? RingLayout.stackedDiameter(in: size, count: 3,
                                         gutter: RingLayout.stackedGutter,
                                         labelWidth: ringLabelWidth, floor: 20)
            : RingLayout.diameter(in: size, count: 3, gutter: RingLayout.compactGutter,
                                  labelHeight: ringLabelHeight, floor: 20,
                                  cap: RingLayout.compactMaxDiameter)
    }

    private var minimalGauges: some View {
        spread(minGap: MetricBlock.compactGap, maxGap: MetricBlock.compactGapMax) { metric in
            CompactMinimalRow(label: metric.label, percent: metric.percent,
                              fraction: metric.fraction)
        }
    }

    private func spread<Row: View>(minGap: CGFloat, maxGap: CGFloat,
                                   @ViewBuilder row: @escaping (MetricDatum) -> Row) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(MetricDatum.all(for: snapshot).enumerated()),
                    id: \.element.id) { index, metric in
                if index > 0 { Spacer(minLength: minGap).frame(maxHeight: maxGap) }
                row(metric)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Traffic

    private var traffic: some View {
        TrafficGrid(rows: TrafficGrid.rows(for: snapshot), compact: true)
    }

    static func == (lhs: CompactServerCard, rhs: CompactServerCard) -> Bool {
        lhs.host == rhs.host
            && lhs.embedded == rhs.embedded
            && lhs.state == rhs.state
            && lhs.deployment == rhs.deployment
    }
}

struct CompactCombinedServerCard: View, Equatable {
    let deployment: Deployment
    let machines: [(host: SSHHostID, state: ServerHostMetricsState)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let symbol = deployment.iconSymbol {
                    Image(systemName: symbol)
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                        .frame(width: 20, height: 20)
                } else {
                    OSBadge(osID: machines.first?.state.liveSnapshot?.osID,
                            isMultiHost: deployment.isMultiHost)
                }
                Text(deployment.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            ForEach(Array(machines.enumerated()), id: \.offset) { index, machine in
                if index > 0 { Divider() }
                CompactServerCard(deployment: deployment, host: machine.host,
                                  state: machine.state, embedded: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassCardBackground(fallback: GlassPalette.cardBase, tint: deployment.displayTint)
        .tint(deployment.displayTint)
    }

    static func == (lhs: CompactCombinedServerCard, rhs: CompactCombinedServerCard) -> Bool {
        lhs.deployment == rhs.deployment
            && lhs.machines.count == rhs.machines.count
            && zip(lhs.machines, rhs.machines).allSatisfy { $0.host == $1.host && $0.state == $1.state }
    }
}

struct CompactGaugeRow: View {
    let label: String
    let percent: Double?
    let fraction: Double?
    var track = false

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text(verbatim: label)
                    .font(.caption2.weight(.medium))
                Spacer(minLength: 2)
                Text(verbatim: percent.map { MetricsFormat.percent($0) } ?? "—")
                    .font(.caption2)
                    .monospacedDigit()
            }
            .lineLimit(1)
            if track {
                TrackGaugeBar(fraction: fraction ?? 0)
            } else {
                SegmentedGaugeBar(fraction: fraction ?? 0, segmentCount: 12)
            }
        }
    }
}

struct CompactMinimalRow: View {
    let label: String
    let percent: Double?
    let fraction: Double?

    var body: some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(verbatim: percent.map { MetricsFormat.percent($0) } ?? "—")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
            }
            .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(LoadColor.tint(for: fraction ?? 0))
                        .frame(width: max(0, geo.size.width * (fraction ?? 0).clamped(to: 0...1)))
                }
            }
            .frame(height: 3)
        }
    }
}
