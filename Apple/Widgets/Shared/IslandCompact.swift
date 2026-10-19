#if os(iOS)
import SwiftUI

/// Dynamic Island sizes from Apple's Live Activity guidelines
enum IslandCompact {
    /// Compact side on the narrower island; Pro Max allows more
    static let sideLimit: CGFloat = 52
    static let heightLimit: CGFloat = 36

    static let glyph: CGFloat = 18
    static let widestGlyph: CGFloat = 22
    static let narrowestGlyph: CGFloat = 14

    /// Fits a running clock under an hour
    static let timerWidth: CGFloat = 34
    static let widestTimer: CGFloat = 42

    static func glyphDiameter(scaled: CGFloat) -> CGFloat {
        min(max(scaled, narrowestGlyph), widestGlyph)
    }

    static func trailingWidth(scaled: CGFloat) -> CGFloat {
        min(max(scaled, timerWidth), widestTimer)
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
            .frame(width: IslandCompact.trailingWidth(scaled: scaled), alignment: .trailing)
    }
}

/// The compact island's percentage, only as wide as needed
struct CompactIslandPercent: View {
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
