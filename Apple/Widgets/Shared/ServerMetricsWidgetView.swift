import SwiftUI
import VPNTunnel
import WidgetKit

/// One machine's load, as the app last read it
struct ServerMetricsWidgetView: View {
    let entry: ServerMetricsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let server = entry.server, let reading = server.metrics {
            card(server: server, reading: reading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(verbatim: "gryonixNexus")
                } icon: {
                    Image(systemName: "server.rack")
                }
                .font(.caption).foregroundStyle(.secondary)
                Text(entry.available ? "No reading yet" : "Open gryonixNexus")
                    .font(.footnote)
                Text(entry.available
                     ? "Open a server's dashboard once and its load appears here."
                     : "This build cannot share readings with its widgets yet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func card(server: FleetSnapshot.Server,
                      reading: FleetSnapshot.Reading) -> some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: server.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                // The age travels with the numbers, always — see `ServerMetricsPresentation.age`.
                Text(verbatim: ServerMetricsPresentation.age(reading.age))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            if reading.machineLabel != server.name {
                Text(verbatim: reading.machineLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            VStack(spacing: family == .systemSmall ? 4 : 6) {
                LoadBar(name: String(localized: "CPU"), percent: reading.cpuPercent)
                LoadBar(name: String(localized: "Memory"), percent: reading.memoryPercent)
                LoadBar(name: String(localized: "Disk"), percent: reading.diskPercent)
            }
            if server.failure != nil {
                Label("Last attempt failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// One reading: its name, its bar and its number
private struct LoadBar: View {
    let name: String
    let percent: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(verbatim: ServerMetricsPresentation.percent(percent))
                    .font(.caption2.monospacedDigit())
                    .fixedSize()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(ServerMetricsPresentation.tint(percent))
                        .frame(width: geometry.size.width * min(max((percent ?? 0) / 100, 0), 1))
                }
            }
            .frame(height: 4)
        }
    }
}

/// What the timeline hands the view
struct ServerMetricsEntry: TimelineEntry {
    let date: Date
    let server: FleetSnapshot.Server?
    let available: Bool
}
