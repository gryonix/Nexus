import Foundation
import SwiftUI
import VPNTunnel

enum TunnelPresentation {
    /// The one-word state, as a person would say it
    static func title(_ status: TunnelStatus) -> LocalizedStringKey {
        switch status {
        case .off: return "Not connected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .reasserting: return "Reconnecting…"
        case .disconnecting: return "Disconnecting…"
        case .failed: return "Failed"
        }
    }

    static func plainTitle(_ status: TunnelStatus) -> String {
        switch status {
        case .off: return UIL10n.string("Not connected")
        case .connecting: return UIL10n.string("Connecting…")
        case .connected: return UIL10n.string("Connected")
        case .reasserting: return UIL10n.string("Reconnecting…")
        case .disconnecting: return UIL10n.string("Disconnecting…")
        case .failed: return UIL10n.string("Failed")
        }
    }

    static func tint(_ status: TunnelStatus, isSimulated: Bool) -> Color {
        switch status {
        case .connected: return isSimulated ? .orange : .green
        case .reasserting, .connecting, .disconnecting: return .orange
        case .failed: return .red
        case .off: return .secondary
        }
    }

    static func symbol(_ status: TunnelStatus) -> String { status.systemImage }

    @ViewBuilder
    static func mark(_ status: TunnelStatus, size: CGFloat) -> some View {
        if status.isActive {
            BrandMark.vpn(size: size)
        } else {
            Image(systemName: status.systemImage)
        }
    }

    @ViewBuilder
    static func menuBarMark(_ status: TunnelStatus, size: CGFloat) -> some View {
        if status.isActive {
            BrandMark.vpn(size: size)
        } else {
            BrandMark.globeMark(size: size)
        }
    }

    static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .binary))
    }

    /// "↓ 1.2 MB · ↑ 400 KB"
    static func traffic(_ statistics: TunnelStatistics) -> String {
        "↓ \(bytes(statistics.received)) · ↑ \(bytes(statistics.sent))"
    }

    static func age(of date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 90 { return UIL10n.string("just now") }
        return date.formatted(date: .omitted, time: .shortened)
    }

    static var noProfilesNotice: LocalizedStringKey {
        "No tunnel yet. Open a device on one of your servers and choose “Use on this device”."
    }
}

/// The session timer
struct TunnelSessionTimer: View {
    let since: Date
    var font: Font = .body.monospacedDigit()
    /// A bound keeps the timer's reserved width sane
    static let longestShown: TimeInterval = 10_000 * 3600 - 1

    var body: some View {
        Text(timerInterval: since...since.addingTimeInterval(Self.longestShown), countsDown: false)
            .font(font)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

struct DemonstrationNotice: View {
    var compact = false

    var body: some View {
        Label {
            Text(compact
                 ? "Demo — no traffic is protected"
                 : "Demo connection: no tunnel is brought up and no traffic is protected. A real tunnel needs the app signed with the Network Extension capability.")
        } icon: {
            Image(systemName: "theatermasks")
        }
        .font(compact ? .caption2 : .footnote)
        .foregroundStyle(.secondary)
    }
}

enum DemonstrationText {
    static var full: LocalizedStringKey {
        "Demo connection: no tunnel is brought up and no traffic is protected. A real tunnel needs the app signed with the Network Extension capability."
    }

    /// Room for a line — the medium widget, the menu bar
    static var line: LocalizedStringKey { "Demo — no traffic is protected" }

    static var short: LocalizedStringKey { "Demo — not protected" }

    static var badge: LocalizedStringKey { "demo" }
}
