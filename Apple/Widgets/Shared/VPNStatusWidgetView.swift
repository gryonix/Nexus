import SwiftUI
import VPNTunnel
import WidgetKit

struct VPNStatusWidgetView: View {
    let entry: TunnelEntry
    var familyOverride: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily

    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    private var tunnel: TunnelSnapshot { entry.value.tunnel }

    var body: some View {
        switch family {
        #if os(iOS)
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        #endif
        default: standard
        }
    }

    // MARK: - Home screen / desktop

    private var standard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TunnelPresentation.mark(tunnel.status, size: 22)
                    .font(.title2)
                    .foregroundStyle(TunnelPresentation.tint(tunnel.status,
                                                             isSimulated: tunnel.isSimulated))
                Text(TunnelPresentation.title(tunnel.status))
                    .font(.headline)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
            }

            if let since = tunnel.status.activeSince {
                TunnelSessionTimer(since: since, font: .title3.monospacedDigit())
            }

            if let subtitle = tunnel.subtitle {
                Text(verbatim: subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if tunnel.status.isActive {
                Text(verbatim: TunnelPresentation.traffic(tunnel.statistics))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            footnote
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(AppLink.url(for: .tunnel))
    }

    @ViewBuilder
    private var footnote: some View {
        if !entry.available {
            Text("Open gryonixNexus")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if tunnel.profileCount == 0 {
            Text("No tunnel yet")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if tunnel.isSimulated {
            Text(DemonstrationText.line)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Lock screen

    #if os(iOS)
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                TunnelPresentation.mark(tunnel.status, size: 20)
                    .font(.title3)
                if tunnel.isSimulated {
                    Text(DemonstrationText.badge).font(.system(size: 8))
                }
            }
        }
        .widgetURL(AppLink.url(for: .tunnel))
    }

    private var inline: some View {
        Label {
            if let since = tunnel.status.activeSince {
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
            } else {
                Text(TunnelPresentation.title(tunnel.status))
            }
        } icon: {
            TunnelPresentation.mark(tunnel.status, size: 15)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label {
                Text(TunnelPresentation.title(tunnel.status))
            } icon: {
                TunnelPresentation.mark(tunnel.status, size: 17)
            }
            .font(.headline)
            if let since = tunnel.status.activeSince {
                TunnelSessionTimer(since: since, font: .caption.monospacedDigit())
            }
            if tunnel.isSimulated {
                Text(DemonstrationText.short)
                    .font(.caption2)
                    .lineLimit(1)
            } else if let subtitle = tunnel.subtitle {
                Text(verbatim: subtitle)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(AppLink.url(for: .tunnel))
    }
    #endif
}

struct DevicesWidgetView: View {
    let entry: TunnelEntry
    /// See `VPNStatusWidgetView.familyOverride`
    var familyOverride: WidgetFamily?
    @Environment(\.widgetFamily) private var environmentFamily

    private var family: WidgetFamily { familyOverride ?? environmentFamily }
    private var snapshot: FleetSnapshot { entry.value }
    private var isLarge: Bool { family == .systemLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if snapshot.servers.isEmpty {
                Text(entry.available ? "No servers yet" : "Open gryonixNexus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.servers.prefix(isLarge ? 5 : 3)) { server in
                    row(server)
                }
            }
            Spacer(minLength: 0)
            Text(entry.available
                 ? UIL10n.string("Read %@", TunnelPresentation.age(of: snapshot.generatedAt))
                 : UIL10n.string("No reading yet"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(AppLink.url(for: .app))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "iphone.gen3")
                .foregroundStyle(.tint)
            Text(verbatim: "\(snapshot.deviceCount)")
                .font(.headline.monospacedDigit())
            Text("devices")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if snapshot.tunnel.status.isActive {
                TunnelPresentation.mark(snapshot.tunnel.status, size: 16)
                    .foregroundStyle(TunnelPresentation.tint(snapshot.tunnel.status,
                                                             isSimulated: snapshot.tunnel.isSimulated))
            }
        }
    }

    private func row(_ server: FleetSnapshot.Server) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(verbatim: server.name)
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
                if server.failure != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: "\(server.deviceCount)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if isLarge, !server.protocolSummary.isEmpty {
                Text(verbatim: server.protocolSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
