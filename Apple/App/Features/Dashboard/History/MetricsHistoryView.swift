import Charts
import ServerControl
import SwiftUI

struct MetricsHistoryView: View {
    @StateObject private var viewModel: MetricsHistoryViewModel
    /// One or more metrics to plot
    @State private var selection: Set<HistoryMetric>

    init(deployment: Deployment, host: SSHHostID, initialMetric: HistoryMetric? = nil) {
        _viewModel = StateObject(wrappedValue: MetricsHistoryViewModel(deployment: deployment,
                                                                       host: host))
        _selection = State(initialValue: [initialMetric ?? .cpu])
    }

    var body: some View {
        CardList {
            Section {
                MetricsHistoryContent(viewModel: viewModel, selection: $selection)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    .listRowSeparator(.hidden)
            } header: {
                InfoSectionHeader("Metrics history", note: "History is collected on the server; longer ranges fill in over time.")
            }
        }
        .navigationTitle("Metrics history")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await viewModel.start() }
        .onDisappear { viewModel.teardown() }
        .refreshableWithShortcut { await viewModel.load() }
    }
}

/// The user-facing look-back window
enum HistoryRange: String, CaseIterable, Identifiable {
    case tenMinutes = "10m"
    case thirtyMinutes = "30m"
    case hour = "1h"
    case threeHours = "3h"
    case fiveHours = "5h"
    case tenHours = "10h"
    case day = "1d"
    case week = "1w"
    case twelveDays = "12d"
    case month = "1mo"
    case sixMonths = "6mo"
    case year = "1y"

    var id: String { rawValue }

    /// How far back the chart looks
    var span: TimeInterval {
        switch self {
        case .tenMinutes: return 600
        case .thirtyMinutes: return 1_800
        case .hour: return 3_600
        case .threeHours: return 3 * 3_600
        case .fiveHours: return 5 * 3_600
        case .tenHours: return 10 * 3_600
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .twelveDays: return 12 * 86_400
        case .month: return 30 * 86_400
        case .sixMonths: return 182 * 86_400
        case .year: return 365 * 86_400
        }
    }

    var bucket: MetricsHistoryBucket {
        switch self {
        case .tenMinutes, .thirtyMinutes: return .tenSeconds
        case .hour, .threeHours, .fiveHours: return .oneMinute
        case .tenHours, .day: return .tenMinutes
        case .week, .twelveDays: return .oneHour
        case .month, .sixMonths: return .oneDay
        case .year: return .oneWeek
        }
    }
}

struct MetricsHistoryContent: View {
    @ObservedObject var viewModel: MetricsHistoryViewModel
    @Binding var selection: Set<HistoryMetric>

    private var selectedMetrics: [HistoryMetric] {
        HistoryMetric.allCases.filter { selection.contains($0) }
    }

    private var primaryMetric: HistoryMetric { selectedMetrics.first ?? .cpu }

    private var availableMetrics: [HistoryMetric] {
        MetricsPreferences.shared.offeredMetrics
            .filter { $0 != .temperature || viewModel.hasTemperature }
    }

    /// Whether the picker is up
    @State private var choosingMetric = false
    @State private var diskChoice = DiskChoice.average

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                metricMenu
                Spacer()
            }
            chartContent
            RangeSliderBar(selection: $viewModel.range)
        }
    }

    /// What the chart shows, led by the component icon
    private var metricMenu: some View {
        Button { choosingMetric = true } label: {
            HStack(spacing: 6) {
                Image(systemName: primaryMetric.systemImage)
                    .foregroundStyle(primaryMetric.tint)
                Text(primaryMetric.title)
                    .font(.headline)
                if selectedMetrics.count > 1 {
                    Text(verbatim: "+\(selectedMetrics.count - 1)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $choosingMetric) {
            MetricChoiceSheet(offered: availableMetrics, selected: selectedMetrics) { chosen in
                selection = Set(chosen)
            }
        }
    }

    @ViewBuilder
    private var chartContent: some View {
        if let error = viewModel.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .font(.callout)
        } else if viewModel.points.isEmpty {
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(height: 220)
            } else {
                ContentUnavailableView {
                    Label("No history yet", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("History is collected on the server; longer ranges fill in over time.")
                }
                .frame(height: 220)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if let metric = totalsMetric {
                    MetricsTotalsRow(metric: metric, points: viewModel.points,
                                     range: viewModel.range)
                }
                if showsDiskChoice { diskPicker }
                HistoryChart(points: viewModel.points, metrics: selectedMetrics,
                             range: viewModel.range, showsLegend: totalsMetric == nil,
                             diskLines: diskLines)
                    .frame(height: 270)
            }
        }
    }

    private var diskMounts: [String] { DiskHistory.mounts(viewModel.diskPoints) }

    private var showsDiskChoice: Bool { selection.contains(.disk) && diskMounts.count > 1 }

    private var diskLines: [DiskChartLine] {
        guard showsDiskChoice else { return [] }
        return DiskHistory.lines(viewModel.diskPoints, choice: diskChoice).map { line in
            DiskChartLine(name: line.name, values: line.values.map { DiskChartValue(date: $0.date, value: $0.value) })
        }
    }

    private var diskPicker: some View {
        WrappingPicker("Disks", selection: $diskChoice) {
            Text("Average of all disks").tag(DiskChoice.average)
            Text("Each disk separately").tag(DiskChoice.each)
            ForEach(diskMounts, id: \.self) { mount in
                Text(verbatim: mount).tag(DiskChoice.one(mount))
            }
        }
    }

    private var totalsMetric: HistoryMetric? {
        guard selectedMetrics.count == 1, let metric = selectedMetrics.first,
              metric.isTwoSeries else { return nil }
        return metric
    }
}

private struct MetricsTotalsRow: View {
    let metric: HistoryMetric
    let points: [MetricsHistoryPoint]
    let range: HistoryRange

    private var windowed: [MetricsHistoryPoint] { points.windowed(to: range) }

    private func total(_ keyPath: (MetricsHistoryPoint) -> Double?) -> Int64 {
        let interval = range.bucket.pointInterval
        let bytes = windowed.reduce(0.0) { $0 + (keyPath($1) ?? 0) * interval }
        return Int64(bytes)
    }

    private var primaryTotal: Int64 {
        switch metric {
        case .network: return total(\.netReceivedPerSecond)
        case .diskIO: return total(\.diskReadPerSecond)
        default: return 0
        }
    }

    private var secondaryTotal: Int64 {
        switch metric {
        case .network: return total(\.netSentPerSecond)
        case .diskIO: return total(\.diskWrittenPerSecond)
        default: return 0
        }
    }

    private var primaryName: LocalizedStringKey { metric == .network ? "Received" : "Read" }
    private var secondaryName: LocalizedStringKey { metric == .network ? "Sent" : "Write" }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            stat(name: primaryName, color: .blue, value: primaryTotal)
                .frame(maxWidth: .infinity, alignment: .leading)
            stat(name: secondaryName, color: .orange, value: secondaryTotal)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stat(name: LocalizedStringKey, color: Color, value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: MetricsFormat.bytes(value))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

struct MetricsHistoryDisclosure: View {
    let deployment: Deployment
    let host: SSHHostID
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if expanded {
                InlineMetricsHistory(deployment: deployment, host: host)
            }
        } label: {
            Label("Metrics history", systemImage: "chart.xyaxis.line")
        }
    }
}

private struct InlineMetricsHistory: View {
    @StateObject private var viewModel: MetricsHistoryViewModel
    @State private var selection: Set<HistoryMetric> = [.cpu]

    init(deployment: Deployment, host: SSHHostID) {
        _viewModel = StateObject(wrappedValue: MetricsHistoryViewModel(deployment: deployment,
                                                                       host: host))
    }

    var body: some View {
        MetricsHistoryContent(viewModel: viewModel, selection: $selection)
            .padding(.vertical, 4)
            .task { await viewModel.start() }
            .onDisappear { viewModel.teardown() }
    }
}

/// The period selector: our strip or the system segmented control
private struct RangeSliderBar: View {
    @Binding var selection: HistoryRange

    @ObservedObject private var preferences = MetricsPreferences.shared
    @ObservedObject private var bars = TabBarSettings.shared
    private var ranges: [HistoryRange] { preferences.offeredRanges }

    var body: some View {
        picker.sensoryFeedback(.selection, trigger: selection)
    }

    @ViewBuilder private var picker: some View {
        #if os(iOS)
        if bars.periodStripStyle == .custom {
            GlassSegmentStrip(
                items: ranges.map {
                    StripItem(id: $0.rawValue, title: $0.plainTitle,
                              identifier: "metrics.period.\($0.rawValue)")
                },
                selection: Binding(get: { selection.rawValue },
                                   set: { id in
                                       if let range = HistoryRange(rawValue: id) { selection = range }
                                   }),
                identifier: "metrics.periods",
                probe: "periods",
                menu: { _ in nil },
                dragToSwitch: true)
        } else {
            systemPicker
        }
        #else
        systemPicker
        #endif
    }

    private var systemPicker: some View {
        Picker("Period", selection: $selection) {
            ForEach(ranges) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

extension HistoryRange {
    /// Short span in the app's language
    var title: LocalizedStringKey {
        switch self {
        case .tenMinutes: return "10m"
        case .thirtyMinutes: return "30m"
        case .hour: return "1h"
        case .threeHours: return "3h"
        case .fiveHours: return "5h"
        case .tenHours: return "10h"
        case .day: return "1d"
        case .week: return "1w"
        case .twelveDays: return "12d"
        case .month: return "1mo"
        case .sixMonths: return "6mo"
        case .year: return "1y"
        }
    }

    var plainTitle: String { UIL10n.string(rawValue) }
}

/// Which reading the chart plots
enum HistoryMetric: String, CaseIterable, Identifiable {
    case cpu, memory, disk, network, diskIO, load, temperature, power

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        case .diskIO: return "Disk I/O"
        case .load: return "Load"
        case .temperature: return "Temperature"
        case .power: return "Power"
        }
    }

    var plainTitle: String {
        switch self {
        case .cpu: return UIL10n.string("CPU")
        case .memory: return UIL10n.string("Memory")
        case .disk: return UIL10n.string("Disk")
        case .network: return UIL10n.string("Network")
        case .diskIO: return UIL10n.string("Disk I/O")
        case .load: return UIL10n.string("Load")
        case .temperature: return UIL10n.string("Temperature")
        case .power: return UIL10n.string("Power")
        }
    }

    var systemImage: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .diskIO: return "arrow.up.arrow.down.circle"
        case .load: return "gauge.with.needle"
        case .temperature: return "thermometer.medium"
        case .power: return "bolt.fill"
        }
    }

    var tint: Color {
        switch self {
        case .cpu: return .blue
        case .memory: return .purple
        case .disk: return .teal
        case .network: return .green
        case .diskIO: return .pink
        case .load: return .indigo
        case .temperature: return .orange
        case .power: return .yellow
        }
    }

    var isPercent: Bool { self == .cpu || self == .memory || self == .disk }

    static func toggling(_ metric: HistoryMetric, in selection: Set<HistoryMetric>) -> Set<HistoryMetric> {
        guard metric.isPercent else { return [metric] }
        var next = selection.filter(\.isPercent)
        if next.contains(metric) { next.remove(metric) } else { next.insert(metric) }
        return next.isEmpty ? [metric] : next
    }

    var isTwoSeries: Bool { self == .network || self == .diskIO }
}

extension Array where Element == MetricsHistoryPoint {
    /// Points inside the selected window, anchored at the newest row
    func windowed(to range: HistoryRange) -> [MetricsHistoryPoint] {
        guard let newest = last?.date else { return self }
        let start = newest.addingTimeInterval(-range.span)
        return filter { $0.date >= start }
    }
}

/// One chart pane
struct HistoryChart: View, Equatable {
    static func == (lhs: HistoryChart, rhs: HistoryChart) -> Bool {
        lhs.range == rhs.range
            && lhs.showsLegend == rhs.showsLegend
            && lhs.metrics == rhs.metrics
            && lhs.allPoints == rhs.allPoints
            && lhs.diskLines == rhs.diskLines
    }

    let allPoints: [MetricsHistoryPoint]
    let metrics: [HistoryMetric]
    let range: HistoryRange
    let showsLegend: Bool
    /// Per-disk lines that replace the single disk line
    let diskLines: [DiskChartLine]

    init(points: [MetricsHistoryPoint], metrics: [HistoryMetric], range: HistoryRange,
         showsLegend: Bool = true, diskLines: [DiskChartLine] = []) {
        self.allPoints = points
        self.metrics = metrics
        self.range = range
        self.showsLegend = showsLegend
        self.diskLines = diskLines
    }

    private var points: [MetricsHistoryPoint] { allPoints.windowed(to: range) }

    private var xAxisFormat: Date.FormatStyle {
        let day: TimeInterval = 86_400
        if range.span <= day { return .dateTime.hour().minute() }
        if range.span <= 120 * day { return .dateTime.day().month(.abbreviated) }
        return .dateTime.month(.abbreviated).year(.twoDigits)
    }

    @AppStorage(MetricsDisplaySettings.historyAutoScaleKey)
    private var autoScale = true

    @State private var selectedDate: Date?

    private struct Series: Identifiable {
        let name: LocalizedStringKey
        let key: String
        let color: Color
        let values: [(date: Date, value: Double)]
        var id: String { key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            chart
            if showsLegend, series.count > 1 {
                HStack(spacing: 14) {
                    ForEach(series) { series in
                        HStack(spacing: 5) {
                            Circle().fill(series.color).frame(width: 8, height: 8)
                            Text(series.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
    }

    private var chart: some View {
        Chart {
            lineMarks
            if let selectedDate, let selected = nearestPoints(to: selectedDate) {
                RuleMark(x: .value("Date", selected.date))
                    .foregroundStyle(Color.blue.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                ForEach(scrubberDots(at: selected)) { dot in
                    PointMark(x: .value("Date", selected.date), y: .value("Value", dot.y))
                        .foregroundStyle(tooltipBackground)
                        .symbolSize(150)
                    PointMark(x: .value("Date", selected.date), y: .value("Value", dot.y))
                        .foregroundStyle(dot.color)
                        .symbolSize(70)
                }
            }
        }
        .overlay(alignment: calloutAlignment) {
            if let selectedDate, let selected = nearestPoints(to: selectedDate) {
                scrubberLabel(selected)
                    .padding(.trailing, calloutAlignment == .topTrailing ? 52 : 6)
                    .padding(.leading, 6)
                    .padding(.vertical, 6)
                    // Never eats the drag it is describing.
                    .allowsHitTesting(false)
            }
        }
        #if DEBUG
        .onAppear {
            if let raw = ProcessInfo.processInfo.environment["GRYONIXNEXUS_DEMO_SCRUB"],
               let fraction = Double(raw) {
                let span = xDomain.upperBound.timeIntervalSince(xDomain.lowerBound)
                selectedDate = xDomain.lowerBound.addingTimeInterval(span * fraction)
            }
        }
        #endif
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(verbatim: format(doubleValue))
                            .font(.caption2)
                            .monospacedDigit()
                            .padding(.leading, 5)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel(format: xAxisFormat)
                    .font(.caption2)
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                let origin = geometry[proxy.plotFrame!].origin
                                selectedDate = proxy.value(atX: drag.location.x - origin.x)
                            }
                            .onEnded { _ in selectedDate = nil }
                    )
            }
        }
    }

    @ChartContentBuilder
    private var lineMarks: some ChartContent {
        ForEach(series) { series in
            ForEach(series.values, id: \.date) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value),
                    series: .value("Series", series.key)
                )
                .foregroundStyle(series.color)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
            }
        }
    }

    // MARK: - Series extraction

    private var series: [Series] {
        func values(_ keyPath: (MetricsHistoryPoint) -> Double?) -> [(date: Date, value: Double)] {
            points.compactMap { point in keyPath(point).map { (point.date, $0) } }
        }
        var out: [Series] = []
        for metric in metrics {
            switch metric {
            case .cpu:
                out.append(Series(name: "CPU", key: "cpu", color: HistoryMetric.cpu.tint,
                                  values: values(\.cpuPercent)))
            case .memory:
                out.append(Series(name: "Memory", key: "mem", color: HistoryMetric.memory.tint,
                                  values: values { $0.memUsedFraction * 100 }))
            case .disk where !diskLines.isEmpty:
                out += diskSeries
            case .disk:
                out.append(Series(name: "Disk", key: "disk", color: HistoryMetric.disk.tint,
                                  values: values { $0.diskUsedFraction * 100 }))
            case .network:
                out.append(Series(name: "Received", key: "rx", color: .blue,
                                  values: values(\.netReceivedPerSecond)))
                out.append(Series(name: "Sent", key: "tx", color: .orange,
                                  values: values(\.netSentPerSecond)))
            case .diskIO:
                out.append(Series(name: "Read", key: "read", color: .blue,
                                  values: values(\.diskReadPerSecond)))
                out.append(Series(name: "Write", key: "write", color: .orange,
                                  values: values(\.diskWrittenPerSecond)))
            case .load:
                out.append(Series(name: "Load", key: "load", color: HistoryMetric.load.tint,
                                  values: values(\.load1)))
            case .temperature:
                out.append(Series(name: "Temperature", key: "temp", color: HistoryMetric.temperature.tint,
                                  values: values(\.temperatureCelsius)))
            case .power:
                out.append(Series(name: "Power", key: "power", color: HistoryMetric.power.tint,
                                  values: values(\.powerWatts)))
            }
        }
        return out
    }

    private static let diskColors: [Color] = [.teal, .indigo, .orange, .pink, .green, .purple, .brown]

    private var diskSeries: [Series] {
        let start = points.first?.date ?? .distantPast
        return diskLines.enumerated().map { index, line in
            Series(name: line.name.isEmpty ? "Disk" : "\(line.name)", key: "disk-\(line.name)",
                   color: Self.diskColors[index % Self.diskColors.count],
                   values: line.values.filter { $0.date >= start }.map { ($0.date, $0.value) })
        }
    }

    private var isPercentChart: Bool { metrics.allSatisfy(\.isPercent) }

    private var calloutAlignment: Alignment {
        guard let selectedDate else { return .topLeading }
        let span = xDomain.upperBound.timeIntervalSince(xDomain.lowerBound)
        guard span > 0 else { return .topLeading }
        let fraction = selectedDate.timeIntervalSince(xDomain.lowerBound) / span
        return fraction < 0.5 ? .topTrailing : .topLeading
    }

    private var xDomain: ClosedRange<Date> {
        let newest = points.last?.date ?? Date()
        return newest.addingTimeInterval(-range.span)...newest
    }

    private var yDomain: ClosedRange<Double> {
        let values = series.flatMap(\.values).map(\.value)
        guard autoScale else {
            if isPercentChart { return 0...100 }
            return 0...Swift.max((values.max() ?? 1) * 1.15, 1)
        }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        var pad = (high - low) * 0.15
        if pad <= 0 { pad = Swift.max(high * 0.1, isPercentChart ? 2 : 1) }
        var lower = Swift.max(0, low - pad)
        var upper = high + pad
        if isPercentChart {
            lower = Swift.max(0, lower)
            upper = Swift.min(100, Swift.max(upper, lower + 1))
            if upper <= lower { lower = Swift.max(0, upper - 1) }
        }
        return lower...Swift.max(upper, lower + 0.001)
    }

    private func format(_ value: Double) -> String {
        if isPercentChart { return "\(Int(value))%" }
        // Non-percent metrics are always shown alone.
        switch metrics.first ?? .cpu {
        case .network, .diskIO:
            return MetricsFormat.bytes(Int64(value)) + "/s"
        case .load:
            return MetricsFormat.load(value)
        case .temperature:
            return MetricsFormat.temperature(value)
        case .power:
            return EnergyFormat.watts(value)
        default:
            return "\(Int(value))%"
        }
    }

    // MARK: - Scrubber

    private func scrubberDots(at point: MetricsHistoryPoint) -> [ScrubberDot] {
        series.compactMap { series in
            guard let value = series.values.first(where: { $0.date == point.date })?.value else {
                return nil
            }
            return ScrubberDot(id: series.key, y: value, color: series.color)
        }
    }

    private struct ScrubberDot: Identifiable {
        let id: String
        let y: Double
        let color: Color
    }

    private func nearestPoints(to date: Date) -> MetricsHistoryPoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func scrubberLabel(_ point: MetricsHistoryPoint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(point.date, format: .dateTime.day().month().hour().minute())
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(series) { series in
                if let value = series.values.first(where: { $0.date == point.date })?.value {
                    HStack(spacing: 4) {
                        Circle().fill(series.color).frame(width: 6, height: 6)
                        Text(verbatim: format(value))
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(6)
        .background(tooltipBackground, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.quaternary)
        }
    }

    private var tooltipBackground: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

/// One disk's line on the chart
struct DiskChartLine: Equatable {
    let name: String
    let values: [DiskChartValue]
}

struct DiskChartValue: Equatable {
    let date: Date
    let value: Double
}
