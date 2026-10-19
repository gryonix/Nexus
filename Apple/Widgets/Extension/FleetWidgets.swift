import AppIntents
import SwiftUI
import VPNTunnel
import WidgetKit

private enum FleetTimeline {
    static func servers() -> [FleetSnapshot.Server] {
        FleetSnapshotStore().read()?.servers ?? []
    }

    static func chosen(_ configuration: ServerSelectionConfiguration,
                       where has: (FleetSnapshot.Server) -> Bool) -> ServerSectionEntry {
        let snapshot = FleetSnapshotStore().read()
        let servers = snapshot?.servers ?? []
        let server = configuration.server.flatMap { choice in
            servers.first { $0.id == choice.id }
        } ?? servers.first(where: has)
        return ServerSectionEntry(date: Date(), server: server, available: snapshot != nil)
    }
}

/// "Is everything fine" for the whole fleet
struct FleetHealthWidget: Widget {
    static let kind = "gryonixNexus.FleetHealth"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: Provider()) { entry in
            FleetHealthWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fleet")
        .description("How many services need attention, across every server.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> FleetEntry {
            FleetEntry(date: Date(), snapshot: .placeholder, available: true)
        }

        func getSnapshot(in context: Context, completion: @escaping (FleetEntry) -> Void) {
            let store = FleetSnapshotStore().read()
            completion(context.isPreview
                       ? placeholder(in: context)
                       : FleetEntry(date: Date(), snapshot: store, available: store != nil))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<FleetEntry>) -> Void) {
            let store = FleetSnapshotStore().read()
            completion(Timeline(entries: [FleetEntry(date: Date(), snapshot: store,
                                                     available: store != nil)],
                                policy: .never))
        }
    }
}

struct SecurityWidget: Widget {
    static let kind = "gryonixNexus.Security"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind,
                               intent: ServerSelectionConfiguration.self,
                               provider: Provider()) { entry in
            SecurityWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Security")
        .description("Attacks blocked on one server, as the app last read them.")
        .supportedFamilies([.systemSmall])
    }

    struct Provider: AppIntentTimelineProvider {
        func placeholder(in context: Context) -> ServerSectionEntry {
            ServerSectionEntry(date: Date(),
                               server: FleetSnapshot.placeholder.servers.first,
                               available: true)
        }

        func snapshot(for configuration: ServerSelectionConfiguration,
                      in context: Context) async -> ServerSectionEntry {
            context.isPreview ? placeholder(in: context)
                              : FleetTimeline.chosen(configuration) { $0.security != nil }
        }

        func timeline(for configuration: ServerSelectionConfiguration,
                      in context: Context) async -> Timeline<ServerSectionEntry> {
            Timeline(entries: [FleetTimeline.chosen(configuration) { $0.security != nil }],
                     policy: .never)
        }
    }
}

struct BackupsWidget: Widget {
    static let kind = "gryonixNexus.Backups"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind,
                               intent: ServerSelectionConfiguration.self,
                               provider: Provider()) { entry in
            BackupsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Backups")
        .description("Whether unattended backups are armed, and over how much.")
        .supportedFamilies([.systemSmall])
    }

    struct Provider: AppIntentTimelineProvider {
        func placeholder(in context: Context) -> ServerSectionEntry {
            ServerSectionEntry(date: Date(),
                               server: FleetSnapshot.placeholder.servers.first,
                               available: true)
        }

        func snapshot(for configuration: ServerSelectionConfiguration,
                      in context: Context) async -> ServerSectionEntry {
            context.isPreview ? placeholder(in: context)
                              : FleetTimeline.chosen(configuration) { $0.backups != nil }
        }

        func timeline(for configuration: ServerSelectionConfiguration,
                      in context: Context) async -> Timeline<ServerSectionEntry> {
            Timeline(entries: [FleetTimeline.chosen(configuration) { $0.backups != nil }],
                     policy: .never)
        }
    }
}

struct UpdatesWidget: Widget {
    static let kind = "gryonixNexus.Updates"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind,
                               intent: ServerSelectionConfiguration.self,
                               provider: Provider()) { entry in
            UpdatesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Updates")
        .description("How many services on one server have something to pull.")
        .supportedFamilies([.systemSmall])
    }

    struct Provider: AppIntentTimelineProvider {
        func placeholder(in context: Context) -> ServerSectionEntry {
            ServerSectionEntry(date: Date(),
                               server: FleetSnapshot.placeholder.servers.first,
                               available: true)
        }

        func snapshot(for configuration: ServerSelectionConfiguration,
                      in context: Context) async -> ServerSectionEntry {
            context.isPreview ? placeholder(in: context)
                              : FleetTimeline.chosen(configuration) { $0.updates != nil }
        }

        func timeline(for configuration: ServerSelectionConfiguration,
                      in context: Context) async -> Timeline<ServerSectionEntry> {
            Timeline(entries: [FleetTimeline.chosen(configuration) { $0.updates != nil }],
                     policy: .never)
        }
    }
}
