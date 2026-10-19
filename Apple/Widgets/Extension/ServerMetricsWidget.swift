import AppIntents
import SwiftUI
import VPNTunnel
import WidgetKit

struct ServerMetricsWidget: Widget {
    static let kind = "gryonixNexus.ServerMetrics"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind,
                               intent: ServerSelectionConfiguration.self,
                               provider: Provider()) { entry in
            ServerMetricsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Server load")
        .description("CPU, memory and disk of one server, as the app last read them.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    struct Provider: AppIntentTimelineProvider {
        func placeholder(in context: Context) -> ServerMetricsEntry {
            ServerMetricsEntry(date: Date(),
                               server: FleetSnapshot.placeholder.servers.first,
                               available: true)
        }

        func snapshot(for configuration: ServerSelectionConfiguration,
                      in context: Context) async -> ServerMetricsEntry {
            context.isPreview ? placeholder(in: context) : entry(for: configuration)
        }

        func timeline(for configuration: ServerSelectionConfiguration,
                      in context: Context) async -> Timeline<ServerMetricsEntry> {
            Timeline(entries: [entry(for: configuration)], policy: .never)
        }

        private func entry(for configuration: ServerSelectionConfiguration) -> ServerMetricsEntry {
            let snapshot = FleetSnapshotStore().read()
            let servers = snapshot?.servers ?? []
            let chosen = configuration.server.flatMap { choice in
                servers.first { $0.id == choice.id }
            } ?? servers.first { $0.metrics != nil }
            return ServerMetricsEntry(date: Date(), server: chosen, available: snapshot != nil)
        }
    }
}
