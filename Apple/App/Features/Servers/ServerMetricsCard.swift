import ServerControl
import ServiceCatalog
import SwiftUI

struct MetricDatum: Identifiable {
    let label: String
    let detail: String
    let percent: Double?
    let fraction: Double?
    var id: String { label }

    static func all(for snapshot: HostMetricsSnapshot?) -> [MetricDatum] {
        [
            MetricDatum(label: "CPU",
                        detail: snapshot.map { "\($0.cpuCores) C" } ?? "—",
                        percent: snapshot?.cpuPercent,
                        fraction: (snapshot?.cpuPercent).map { $0 / 100 }),
            MetricDatum(label: UIL10n.string("metric.mem"),
                        detail: snapshot.map {
                            "\(MetricsFormat.bytes($0.memUsedBytes)) / \(MetricsFormat.bytes($0.memTotalBytes))"
                        } ?? "—",
                        percent: snapshot.map { $0.memUsedFraction * 100 },
                        fraction: snapshot?.memUsedFraction),
            MetricDatum(label: UIL10n.string("Disk"),
                        detail: snapshot.map {
                            "\(MetricsFormat.bytes($0.diskUsedBytes)) / \(MetricsFormat.bytes($0.diskTotalBytes))"
                        } ?? "—",
                        percent: snapshot.map { $0.diskUsedFraction * 100 },
                        fraction: snapshot?.diskUsedFraction)
        ]
    }
}

/// What one machine is called on a card's badge strip
enum HostBadgeTitle {
    static func of(_ host: SSHHostID, in deployment: Deployment) -> String {
        switch host.kind {
        case .slot(.home): return UIL10n.string("Local")
        case .slot(.vps): return UIL10n.string("VPS")
        case .node(let id):
            guard let node = deployment.nodes.first(where: { $0.id == id }) else {
                return UIL10n.string("Server")
            }
            return node.name.isEmpty ? node.endpoint.host : node.name
        }
    }
}

enum MetricBlock {
    /// The wide card
    static let wide: CGFloat = 93
    /// The half-width card, whose rows are a type size smaller
    static let compact: CGFloat = 75
    /// The least air between two rows
    static let wideGap: CGFloat = 4
    static let compactGap: CGFloat = 3
    static let wideGapMax: CGFloat = 10
    static let compactGapMax: CGFloat = 8
    static let wideTrafficGap: CGFloat = 6
    /// Between the network line and the disk line under it
    static let trafficLineGap: CGFloat = 2
}

/// How big a ring is drawn in that block
enum RingLayout {
    static func diameter(in size: CGSize, count: Int, gutter: CGFloat,
                         labelHeight: CGFloat, floor: CGFloat, cap: CGFloat,
                         outerAir: Bool = true) -> CGFloat {
        let rings = CGFloat(max(count, 1))
        let gutters = CGFloat(outerAir ? max(count, 1) : max(count - 1, 0))
        let byWidth = (size.width - gutter * gutters) / rings
        return max(floor, min(byWidth, size.height - labelHeight, cap))
    }

    static func stackedDiameter(in size: CGSize, count: Int, gutter: CGFloat,
                                labelWidth: CGFloat, floor: CGFloat) -> CGFloat {
        let rings = CGFloat(max(count, 1))
        let gutters = CGFloat(max(count - 1, 0))
        let byHeight = (size.height - gutter * gutters) / rings
        let byWidth = size.width - labelWidth - trailingLabelGap
        return max(floor, min(byWidth, byHeight))
    }

    static func stacks(in size: CGSize, count: Int, gutter: CGFloat,
                       stackedGutter: CGFloat, labelHeight: CGFloat,
                       labelWidth: CGFloat, floor: CGFloat, cap: CGFloat) -> Bool {
        stackedDiameter(in: size, count: count, gutter: stackedGutter,
                        labelWidth: labelWidth, floor: floor)
            > diameter(in: size, count: count, gutter: gutter,
                       labelHeight: labelHeight, floor: floor, cap: cap)
    }

    static let labelHeight: CGFloat = 17
    static let trailingLabelWidth: CGFloat = 46
    static let trailingLabelGap: CGFloat = 10
    static let wideGutter: CGFloat = 12
    static let compactGutter: CGFloat = 7
    static let wideMaxDiameter: CGFloat = (MetricBlock.wide - labelHeight) * 2
    static let compactMaxDiameter: CGFloat = (MetricBlock.compact - labelHeight) * 2
    /// Air between rings STACKED one under another
    static let stackedGutter: CGFloat = 14
}

struct ServerMetricsCard: View, Equatable {
    let deployment: Deployment
    /// Which machine this card shows — scenario B renders two cards
    let host: SSHHostID
    let state: ServerHostMetricsState
    var embedded = false

    @AppStorage(MetricsDisplaySettings.indicatorStyleKey)
    private var indicatorStyleRaw = MetricsIndicatorStyle.bars.rawValue

    /// Only a reading that is still true — see `liveSnapshot`
    private var snapshot: HostMetricsSnapshot? { state.liveSnapshot }
    /// The deployment's own style wins over the app-level default
    private var indicatorStyle: MetricsIndicatorStyle {
        deployment.metricsIndicatorStyle
            ?? MetricsDisplaySettings.indicatorStyle(from: indicatorStyleRaw)
    }

    var body: some View {
        if embedded {
            content
        } else {
            content
                .padding(14)
                // The card surface carries the server's own colour.
                .glassCardBackground(fallback: GlassPalette.cardBase, tint: deployment.displayTint)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            metricsRow
        }
        // Per-server accent colors the capsules/icon; nil → the app accent.
        .tint(deployment.displayTint)
    }

    @ViewBuilder
    private var metricsRow: some View {
        if state.errorMessage != nil {
            ServerOfflineNote(deployment: deployment, host: host, lastSeen: state.lastSeen,
                              offlineSince: state.offlineSince)
                .frame(minHeight: metricsBlockHeight)
        } else {
            VStack(alignment: .leading, spacing: MetricBlock.wideTrafficGap) {
                gauges
                trafficLine
            }
        }
    }

    private var trafficLine: some View {
        TrafficGrid(rows: TrafficGrid.rows(for: snapshot))
    }

    @ScaledMetric(relativeTo: .caption) private var metricsBlockHeight = MetricBlock.wide

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
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
            serviceIcons
            Spacer(minLength: 8)
            headerStatus
        }
    }

    /// The user's custom icon when set, otherwise the OS/topology badge
    @ViewBuilder
    private var leadingBadge: some View {
        if let symbol = deployment.iconSymbol {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 22, height: 22)
        } else {
            OSBadge(osID: snapshot?.osID, isMultiHost: deployment.isMultiHost)
        }
    }

    /// "VPS" / "Local" capsule used whenever two machines share the screen
    private var hostBadge: some View {
        Text(hostBadgeTitle)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.18), in: Capsule())
            .foregroundStyle(.tint)
    }

    /// What to call this machine on its strip
    private var hostBadgeTitle: String {
        HostBadgeTitle.of(host, in: deployment)
    }

    /// Our addition to the NeoServer layout: which services run here
    @ViewBuilder
    private var serviceIcons: some View {
        let services = deployment.installedServices
        if host == deployment.servicesHost, !services.isEmpty {
            ViewThatFits(in: .horizontal) {
                ForEach(Array(stride(from: services.count, through: 0, by: -1)), id: \.self) { shown in
                    serviceIconStrip(services, shown: shown)
                }
            }
        }
    }

    private func serviceIconStrip(_ services: [any ManagedService], shown: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(services.prefix(shown), id: \.id) { service in
                Image(systemName: service.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if shown < services.count {
                Text(verbatim: "+\(services.count - shown)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var headerStatus: some View {
        if let snapshot {
            HStack(spacing: 10) {
                if state.errorMessage != nil {
                    // Stale data: the last reading stays up, marked unreachable.
                    Image(systemName: "wifi.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let temperature = snapshot.temperatureCelsius {
                    statusItem("thermometer.medium",
                               MetricsFormat.temperature(temperature),
                               color: temperature < 70 ? .green : .orange)
                }
                if !snapshot.isPartial {
                    statusItem("clock", MetricsFormat.uptime(snapshot.uptimeSeconds))
                }
                statusItem("chart.xyaxis.line", MetricsFormat.load(snapshot.load1))
            }
        } else if let error = state.errorMessage {
            Image(systemName: "wifi.exclamationmark")
                .font(.caption)
                .foregroundStyle(.red)
                .help(error)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    private func statusItem(_ systemImage: String, _ text: String,
                            color: Color = .secondary) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(text)
                .font(.caption)
                .monospacedDigit()
        }
        .foregroundStyle(color)
        // Status items never wrap; the server name truncates instead.
        .fixedSize()
    }

    private var metricData: [MetricDatum] { MetricDatum.all(for: snapshot) }

    /// The chosen indicator, in the block every indicator gets
    private var gauges: some View {
        indicator
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: metricsBlockHeight, maxHeight: .infinity)
    }

    @ViewBuilder
    private var indicator: some View {
        switch indicatorStyle {
        case .bars: linearGauges(track: false)
        case .track: linearGauges(track: true)
        case .rings: ringGauges
        case .minimal: minimalGauges
        }
    }

    /// Segmented bars (default) or one continuous track per metric
    private func linearGauges(track: Bool) -> some View {
        spread(minGap: MetricBlock.wideGap, maxGap: MetricBlock.wideGapMax) { m in
            GaugeRow(label: m.label, detail: m.detail, percent: m.percent,
                     fraction: m.fraction, track: track)
        }
    }

    private var ringGauges: some View {
        GeometryReader { geo in
            let diameter = ringDiameter(in: geo.size)
            HStack(spacing: RingLayout.wideGutter) {
                ForEach(metricData) { m in
                    RingGauge(label: m.label, fraction: m.fraction, diameter: diameter)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ScaledMetric(relativeTo: .caption2) private var ringLabelHeight = RingLayout.labelHeight

    private func ringDiameter(in size: CGSize) -> CGFloat {
        RingLayout.diameter(in: size, count: metricData.count,
                            gutter: RingLayout.wideGutter,
                            labelHeight: ringLabelHeight, floor: 24,
                            cap: RingLayout.wideMaxDiameter,
                            outerAir: false)
    }

    private var minimalGauges: some View {
        spread(minGap: MetricBlock.wideGap, maxGap: MetricBlock.wideGapMax) { m in
            MinimalMetricRow(label: m.label, percent: m.percent, fraction: m.fraction)
        }
    }

    private func spread<Row: View>(minGap: CGFloat, maxGap: CGFloat,
                                   @ViewBuilder row: @escaping (MetricDatum) -> Row) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(metricData.enumerated()), id: \.element.id) { index, m in
                if index > 0 { Spacer(minLength: minGap).frame(maxHeight: maxGap) }
                row(m)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    static func == (lhs: ServerMetricsCard, rhs: ServerMetricsCard) -> Bool {
        lhs.host == rhs.host
            && lhs.embedded == rhs.embedded
            && lhs.state == rhs.state
            && lhs.deployment == rhs.deployment
    }
}

struct CombinedServerCard: View, Equatable {
    let deployment: Deployment
    /// One entry per machine, in the deployment's own node order
    let machines: [(host: SSHHostID, state: ServerHostMetricsState)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let symbol = deployment.iconSymbol {
                    Image(systemName: symbol)
                        .font(.headline)
                        .foregroundStyle(.tint)
                        .frame(width: 22, height: 22)
                } else {
                    OSBadge(osID: machines.first?.state.liveSnapshot?.osID,
                            isMultiHost: deployment.isMultiHost)
                }
                Text(deployment.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(machinesTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.18), in: Capsule())
                    .foregroundStyle(.tint)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            ForEach(Array(machines.enumerated()), id: \.offset) { index, machine in
                if index > 0 { Divider() }
                ServerMetricsCard(deployment: deployment, host: machine.host,
                                  state: machine.state, embedded: true)
            }
        }
        .padding(16)
        .glassCardBackground(fallback: GlassPalette.cardBase, tint: deployment.displayTint)
        // Per-server accent colors the header capsule (embedded cards tint themselves).
        .tint(deployment.displayTint)
    }

    private var machinesTitle: String {
        if machines.count == 2,
           machines.contains(where: { $0.host == .vps }),
           machines.contains(where: { $0.host == .home }) {
            return UIL10n.string("VPS + Local server")
        }
        return UIL10n.string("%lld servers", machines.count)
    }

    static func == (lhs: CombinedServerCard, rhs: CombinedServerCard) -> Bool {
        lhs.deployment == rhs.deployment
            && lhs.machines.count == rhs.machines.count
            && zip(lhs.machines, rhs.machines).allSatisfy { $0.host == $1.host && $0.state == $1.state }
    }
}

/// "CPU 2 C 
struct GaugeRow: View {
    let label: String
    let detail: String
    let percent: Double?
    let fraction: Double?
    var track = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(verbatim: label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .revealsFullText(label)
                Text(verbatim: detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
                Spacer(minLength: 4)
                Text(verbatim: percent.map { MetricsFormat.percent($0) } ?? "—")
                    .font(.caption)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if track {
                TrackGaugeBar(fraction: fraction ?? 0)
            } else {
                SegmentedGaugeBar(fraction: fraction ?? 0)
            }
        }
    }
}

struct TrackGaugeBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(LoadColor.tint(for: fraction))
                    .frame(width: max(0, geo.size.width * fraction.clamped(to: 0...1)))
            }
        }
        .frame(height: 6)
    }
}

struct MinimalMetricRow: View {
    let label: String
    let percent: Double?
    let fraction: Double?

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(verbatim: percent.map { MetricsFormat.percent($0) } ?? "—")
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
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

struct RingGauge: View {
    let label: String
    let fraction: Double?
    var diameter: CGFloat = 66

    private var lineWidth: CGFloat { max(4.5, diameter * 0.106) }

    private var readingFont: Font {
        .system(size: max(11, min(diameter * 0.26, 24)), weight: .medium)
    }

    /// Where the metric's name is written
    enum LabelPlacement {
        case below
        case trailing
    }

    var labelPlacement: LabelPlacement = .below

    var body: some View {
        switch labelPlacement {
        case .below:
            VStack(spacing: 2) {
                circle
                name
            }
        case .trailing:
            HStack(spacing: RingLayout.trailingLabelGap) {
                circle
                name
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var inset: CGFloat { lineWidth / 2 }

    private var circle: some View {
        ZStack {
            Circle()
                .inset(by: inset)
                .stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .inset(by: inset)
                .trim(from: 0, to: (fraction ?? 0).clamped(to: 0...1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: fraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                .font(readingFont)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: diameter, height: diameter)
    }

    private var name: some View {
        Text(verbatim: label)
            .font(labelPlacement == .below ? .caption2 : .subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var tint: Color {
        LoadColor.tint(for: fraction ?? 0)
    }
}

/// What names the two directions of one reading
enum TrafficLegend {
    case network
    case disk

    var up: (word: String, arrow: String) {
        switch self {
        case .network: return (UIL10n.string("traffic.upload"), "arrow.up")
        case .disk: return (UIL10n.string("Read"), "arrow.up")
        }
    }

    var down: (word: String, arrow: String) {
        switch self {
        case .network: return (UIL10n.string("traffic.download"), "arrow.down")
        case .disk: return (UIL10n.string("Write"), "arrow.down")
        }
    }
}

struct TrafficGrid: View {
    struct Row: Identifiable {
        let title: String
        let legend: TrafficLegend
        let up: Double?
        let down: Double?
        var id: String { title }
    }

    let rows: [Row]
    var compact = false

    static func rows(for snapshot: HostMetricsSnapshot?) -> [Row] {
        [Row(title: UIL10n.string("Network"), legend: .network,
             up: snapshot?.netSentPerSecond, down: snapshot?.netReceivedPerSecond),
         Row(title: UIL10n.string("Disk"), legend: .disk,
             up: snapshot?.diskReadPerSecond, down: snapshot?.diskWrittenPerSecond)]
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            grid(worded: true)
            grid(worded: false)
        }
        .lineLimit(1)
    }

    private var font: Font { compact ? .caption2 : .caption }

    private func grid(worded: Bool) -> some View {
        Grid(alignment: .leading, horizontalSpacing: compact ? 2 : 4,
             verticalSpacing: MetricBlock.trafficLineGap) {
            ForEach(rows) { row in
                GridRow {
                    Text(verbatim: row.title)
                        .font(font)
                        .foregroundStyle(.secondary)
                    Color.clear
                        .frame(minWidth: compact ? 2 : 8, idealWidth: compact ? 2 : 8,
                               maxWidth: .infinity)
                        .gridCellUnsizedAxes(.vertical)
                    legend(row.legend.up, worded: worded)
                    value(row.up)
                    legend(row.legend.down, worded: worded)
                        .padding(.leading, compact ? 3 : 8)
                    value(row.down)
                }
            }
        }
    }

    /// The word, or the arrow it falls back to
    @ViewBuilder
    private func legend(_ legend: (word: String, arrow: String), worded: Bool) -> some View {
        if worded {
            Text(verbatim: legend.word)
                .font(font)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
        } else {
            Image(systemName: legend.arrow)
                .font(.system(size: compact ? 7 : 8, weight: .bold))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
        }
    }

    private func value(_ value: Double?) -> some View {
        Text(verbatim: value.map { MetricsFormat.bytes(Int64($0)) } ?? "—")
            .font(font)
            .monospacedDigit()
            .gridColumnAlignment(.trailing)
    }
}

enum LoadColor {
    static func tint(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: return .green
        case ..<0.85: return .yellow
        case ..<0.95: return .orange
        default: return .red
        }
    }
}

struct SegmentedGaugeBar: View {
    let fraction: Double
    var segmentCount = 24

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                    .fill(color(at: index))
                    .frame(height: 5)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func color(at index: Int) -> Color {
        let filled = Double(index) < fraction.clamped(to: 0...1) * Double(segmentCount) - 0.001
        guard filled else { return Color.primary.opacity(0.12) }
        let position = Double(index + 1) / Double(segmentCount)
        switch position {
        case ..<0.6: return .green
        case ..<0.85: return .yellow
        default: return .orange
        }
    }
}

/// "Net" / "I/O" column: ↑ rate over total, ↓ rate over total

struct OSBadge: View {
    let osID: String?
    let isMultiHost: Bool

    var body: some View {
        if let osID, let style = Self.styles[osID] {
            Circle()
                .fill(style.color.gradient)
                .frame(width: 22, height: 22)
                .overlay {
                    Text(verbatim: style.letter)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
        } else {
            Image(systemName: isMultiHost
                  ? "point.3.connected.trianglepath.dotted" : "server.rack")
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 22, height: 22)
        }
    }

    private static let styles: [String: (letter: String, color: Color)] = [
        "debian": ("D", .red),
        "ubuntu": ("U", .orange),
        "raspbian": ("R", .pink),
        "fedora": ("F", .blue),
        "centos": ("C", .purple),
        "rhel": ("R", .red),
        "rocky": ("R", .green),
        "almalinux": ("A", .indigo),
        "arch": ("A", .cyan),
        "alpine": ("A", .blue),
        "opensuse-leap": ("S", .green),
        "opensuse-tumbleweed": ("S", .green)
    ]
}

enum MetricsFormat {
    static func bytes(_ value: Int64) -> String {
        let units = ["B", "K", "M", "G", "T", "P"]
        var scaled = Double(max(0, value))
        var unit = 0
        while scaled >= 1024, unit < units.count - 1 {
            scaled /= 1024
            unit += 1
        }
        return "\(trim(scaled)) \(units[unit])"
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.1f %%", value)
    }

    static func load(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    static func temperature(_ celsius: Double) -> String {
        String(format: "%.0f°C", celsius)
    }

    /// "90d", "9d 11h", "5h 12m", "34m" — coarse on purpose
    static func uptime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let days = total / 86_400
        let hours = (total % 86_400) / 3600
        let minutes = (total % 3600) / 60
        if days >= 30 { return "\(days)d" }
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private static func trim(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(format: "%.0f", rounded)
            : String(format: "%.1f", rounded)
    }
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
