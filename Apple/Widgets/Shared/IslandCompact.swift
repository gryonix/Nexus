#if os(iOS) || os(tvOS)
import SwiftUI

/// Dynamic Island sizes from Apple's Live Activity guidelines
enum IslandCompact {
    /// Compact side on the narrower island; Pro Max allows more
    static let sideLimit: CGFloat = 52
    static let heightLimit: CGFloat = 36

    static let glyph: CGFloat = 18
    static let widestGlyph: CGFloat = 22
    static let narrowestGlyph: CGFloat = 14

    /// Fits a running clock up to "59:59"
    static let timerWidth: CGFloat = 32
    /// Fits a running clock with hours
    static let hoursTimerWidth: CGFloat = 42
    static let widestTimer: CGFloat = 52
    /// Hours get their room a little before they show
    static let hoursFrom: TimeInterval = 55 * 60

    static func glyphDiameter(scaled: CGFloat) -> CGFloat {
        min(max(scaled, narrowestGlyph), widestGlyph)
    }

    /// The clock's room, wider once it shows hours
    static func trailingWidth(scaled: CGFloat, elapsed: TimeInterval = 0) -> CGFloat {
        let room = elapsed < hoursFrom ? timerWidth : hoursTimerWidth
        return min(max(scaled * room / timerWidth, room), widestTimer)
    }
}

/// A glyph that follows the text size inside the island
struct CompactIslandGlyph<Content: View>: View {
    @ScaledMetric(relativeTo: .caption2) private var scaled: CGFloat = IslandCompact.glyph
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        content(IslandCompact.glyphDiameter(scaled: scaled))
    }
}

/// The running clock in the compact island
struct CompactIslandTimer: View {
    let since: Date
    @ScaledMetric(relativeTo: .caption2) private var scaled: CGFloat = IslandCompact.timerWidth

    var body: some View {
        TunnelSessionTimer(since: since, font: .caption2.monospacedDigit().weight(.semibold))
            .frame(width: IslandCompact.trailingWidth(scaled: scaled, elapsed: Date().timeIntervalSince(since)),
                   alignment: .trailing)
    }
}

/// A short compact-island label, only as wide as needed
struct CompactIslandLabel: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(verbatim: text)
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .fixedSize()
    }
}
#endif
