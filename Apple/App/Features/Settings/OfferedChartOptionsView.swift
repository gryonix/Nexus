import SwiftUI

/// Which periods the chart's slider offers
struct OfferedRangesView: View {
    @ObservedObject private var preferences = MetricsPreferences.shared

    var body: some View {
        Form {
            Section {
                ForEach(HistoryRange.allCases) { range in
                    Toggle(isOn: Binding(
                        get: { preferences.offeredRanges.contains(range) },
                        set: { preferences.setRange(range, offered: $0) }
                    )) {
                        Text(range.title)
                    }
                    .disabled(preferences.offeredRanges == [range])
                }
            } header: {
                InfoSectionHeader("Periods", note: "The periods offered under a chart. Each one reads the collector's own data — this only decides which are on the slider.")
            }
        }
        .formStyle(.grouped)
        .bottomBarClearance()
        .navigationTitle("Periods")
        .raisedNavigationTitle()
    }
}

/// Which metrics a chart's menu offers
struct OfferedMetricsView: View {
    @ObservedObject private var preferences = MetricsPreferences.shared

    var body: some View {
        Form {
            Section {
                ForEach(HistoryMetric.allCases) { metric in
                    Toggle(isOn: Binding(
                        get: { preferences.offeredMetrics.contains(metric) },
                        set: { preferences.setMetric(metric, offered: $0) }
                    )) {
                        Label(metric.title, systemImage: metric.systemImage)
                    }
                    .disabled(preferences.offeredMetrics == [metric])
                }
            } header: {
                InfoSectionHeader("Metrics", note: "Temperature only appears for servers that report one, whether or not it is offered here.")
            }
        }
        .formStyle(.grouped)
        .bottomBarClearance()
        .navigationTitle("Metrics")
        .raisedNavigationTitle()
    }
}
