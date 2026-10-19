#if os(iOS)
import SwiftUI
import VPNTunnel

/// Everything the VPN island draws, without ActivityKit
struct VPNIslandModel {
    var status: TunnelStatus
    var statistics: TunnelStatistics
    var startedAt: Date
    var serverName: String
    var protocolName: String
    var profileName: String
    var isSimulated: Bool
    var style: VPNIslandStyle
    var stopArmed: Bool

    var tint: Color {
        style.color(stateColor: TunnelPresentation.tint(status, isSimulated: isSimulated))
    }
}

/// Keeps island content clear of its rounded sides
enum IslandLayout {
    static let inset: CGFloat = 8
    static let stopDiameter: CGFloat = 40
}

/// The round stop button on the island's right
struct IslandStopButton<Intent: View>: View {
    let isArmed: Bool
    let tint: Color
    @ViewBuilder let wrap: (AnyView) -> Intent

    var body: some View {
        wrap(AnyView(face))
    }

    private var face: some View {
        ZStack {
            Circle()
                .fill(isArmed ? Color.red : tint.opacity(0.22))
            Image(systemName: "stop.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isArmed ? Color.white : tint)
        }
        .frame(width: IslandLayout.stopDiameter, height: IslandLayout.stopDiameter)
        .accessibilityLabel(Text(isArmed ? "Tap again to stop" : "Stop"))
    }
}

struct VPNCompactLeading: View {
    let model: VPNIslandModel

    var body: some View {
        CompactIslandGlyph { size in
            TunnelPresentation.mark(model.status, size: size)
                .foregroundStyle(model.tint)
        }
    }
}

struct VPNCompactTrailing: View {
    let model: VPNIslandModel

    var body: some View {
        switch model.style.compactDetail {
        case .timer:
            CompactIslandTimer(since: model.startedAt)
                .foregroundStyle(model.tint)
        case .protocolName:
            CompactIslandPercent(text: model.style.shortLabel(for: model.protocolName), tint: model.tint)
        case .traffic:
            CompactIslandPercent(text: CompactBytes.of(model.statistics.received), tint: model.tint)
        case .nothing:
            EmptyView()
        }
    }
}

/// Glyph, state and the running clock
struct VPNExpandedLeading: View {
    let model: VPNIslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                VPNCompactLeading(model: model)
                Text(TunnelPresentation.title(model.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if model.style.showsTimer {
                TunnelSessionTimer(since: model.startedAt, font: .title3.monospacedDigit().weight(.semibold))
            }
        }
        .padding(.leading, IslandLayout.inset)
        .frame(maxHeight: .infinity, alignment: .center)
    }
}

/// Server, protocol, traffic and the stop question
struct VPNExpandedBottom: View {
    let model: VPNIslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                if let line = placeLine {
                    Text(verbatim: line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                if model.style.showsTraffic {
                    Text(verbatim: TunnelPresentation.traffic(model.statistics))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            if model.stopArmed {
                Text("Tap stop again to disconnect")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, IslandLayout.inset)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeLine: String? {
        var parts: [String] = []
        if model.style.showsServer { parts.append(model.serverName) }
        if model.style.showsProtocol { parts.append(model.style.fullLabel(for: model.protocolName)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
#endif
