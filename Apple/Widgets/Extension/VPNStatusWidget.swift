import SwiftUI
import VPNTunnel
import WidgetKit

struct VPNStatusWidget: Widget {
    static let kind = "gryonixNexus.Status"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: Provider()) { entry in
            VPNStatusWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("VPN")
        .description("Whether this device's tunnel is up, and for how long.")
        .supportedFamilies(Self.families)
    }

    private static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .accessoryCircular, .accessoryInline, .accessoryRectangular]
        #else
        [.systemSmall]
        #endif
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> TunnelEntry {
            WidgetSnapshotReader.placeholder
        }

        func getSnapshot(in context: Context, completion: @escaping (TunnelEntry) -> Void) {
            completion(context.isPreview ? WidgetSnapshotReader.placeholder
                                         : WidgetSnapshotReader.entry())
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<TunnelEntry>) -> Void) {
            completion(Timeline(entries: [WidgetSnapshotReader.entry()], policy: .never))
        }
    }
}

struct DevicesWidget: Widget {
    static let kind = "gryonixNexus.Devices"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: VPNStatusWidget.Provider()) { entry in
            DevicesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Devices")
        .description("The VPN devices on your servers, as the app last read them.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
