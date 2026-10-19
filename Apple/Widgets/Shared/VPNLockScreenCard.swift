#if os(iOS)
import SwiftUI
import VPNTunnel

/// The VPN session's Lock Screen card, as its style asks
struct VPNLockScreenCard<Stop: View>: View {
    let model: VPNIslandModel
    @ViewBuilder let stop: () -> Stop

    private var style: VPNLockScreenStyle { model.style.lockScreenStyle }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            titleRow
            if let details { detailsLine(details) }
            bottomRow
            if style.showsStopButton, model.stopArmed {
                Text("Tap stop again to disconnect")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                Text(TunnelPresentation.title(model.status))
                    .font(.headline)
            } icon: {
                VPNCompactLeading(model: model)
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            if style.showsTimer {
                TunnelSessionTimer(since: model.startedAt, font: .headline.monospacedDigit())
                    .frame(width: Self.timerWidth, alignment: .trailing)
            }
        }
    }

    /// "example.org · WireGuard · iPhone", trimmed to the chosen parts
    private var details: String? {
        var parts: [String] = []
        if style.showsServer { parts.append(model.serverName) }
        if style.showsProtocol { parts += [model.style.fullLabel(for: model.protocolName), model.profileName] }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func detailsLine(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    @ViewBuilder private var bottomRow: some View {
        if style.showsTraffic || style.showsStopButton || model.isSimulated {
            HStack {
                if style.showsTraffic {
                    Text(verbatim: TunnelPresentation.traffic(model.statistics))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isSimulated { DemonstrationNotice(compact: true) }
                if style.showsStopButton { stop() }
            }
        }
    }

    static var timerWidth: CGFloat { 92 }
}
#endif
