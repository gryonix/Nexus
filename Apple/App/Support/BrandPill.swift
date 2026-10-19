import SwiftUI
#if os(iOS)
import UIKit
#endif

struct BrandPill: View {
    #if os(iOS)
    @AppStorage(AppAccentSettings.choiceKey)
    private var accentRaw = AppAccentSettings.storedChoice().rawValue
    @AppStorage(AppIconSettings.choiceKey)
    private var iconRaw = AppIconChoice.default.rawValue
    #endif

    private static let minimumInset: CGFloat = 30
    private struct Metrics {
        let topY: CGFloat
        let size: CGFloat
        let padding: (horizontal: CGFloat, vertical: CGFloat)
        let plate: CGSize?

        var height: CGFloat { plate?.height ?? (size * 1.2 + padding.vertical * 2) }
        /// Where the plate's bottom edge lands
        var bottom: CGFloat { topY + height }
    }

    private static let islandPlate = CGSize(width: 88, height: 36.7)
    private static let islandBottomGap: CGFloat = 11
    private static let islandClearance: CGFloat = 1.5

    private static func island(topInset: CGFloat) -> Metrics {
        Metrics(topY: topInset - islandBottomGap - islandPlate.height + islandClearance,
                size: 17,
                padding: (horizontal: 0, vertical: 0),
                plate: CGSize(width: islandPlate.width,
                              height: islandPlate.height - islandClearance * 2))
    }

    /// Notch: ends at ~30pt
    private static let notch = Metrics(topY: 5, size: 13,
                                       padding: (horizontal: 10, vertical: 3),
                                       plate: nil)
    private static let islandInset: CGFloat = 55

    static func metrics(topInset: CGFloat) -> (topY: CGFloat, size: CGFloat,
                                               padding: (horizontal: CGFloat, vertical: CGFloat),
                                               plate: CGSize?, height: CGFloat, bottom: CGFloat) {
        let chosen = topInset >= islandInset ? island(topInset: topInset) : notch
        return (chosen.topY, chosen.size, chosen.padding, chosen.plate, chosen.height, chosen.bottom)
    }

    #if os(iOS)
    @State private var topInset: CGFloat = 0
    #endif

    var body: some View {
        #if os(iOS)
        Group {
            if topInset > Self.minimumInset {
                mark
                    .offset(y: Self.metrics(topInset: topInset).topY - topInset)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .allowsHitTesting(false)
        .task {
            for _ in 0..<20 {
                let inset = Self.windowTopInset()
                if inset > 0 { topInset = inset; break }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        #endif
    }

    private var mark: some View {
        #if os(iOS)
        let metrics = Self.metrics(topInset: topInset)
        return Text(verbatim: "gryonix")
            .font(.system(size: metrics.size, weight: .semibold, design: .rounded))
            .kerning(0.2)
            .foregroundStyle(ink)
            .padding(.horizontal, metrics.padding.horizontal)
            .padding(.vertical, metrics.padding.vertical)
            .frame(width: metrics.plate?.width, height: metrics.plate?.height)
            .background(plate, in: Capsule())
        #else
        return Text(verbatim: "gryonix")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .kerning(0.2)
            .foregroundStyle(.primary)
        #endif
    }

    #if os(iOS)
    private var accent: AppAccentChoice { AppAccentChoice(rawValue: accentRaw) ?? .app }
    private var icon: AppIconChoice { AppIconChoice(rawValue: iconRaw) ?? .default }

    /// The plate's colour
    private var plate: Color { accent.tint(icon: icon) ?? Color.accentColor }

    /// Black or white, whichever the plate can be read against
    private var ink: Color {
        let resolved = UIColor(plate).resolvedColor(with: .current)
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getWhite(&white, alpha: &alpha) else { return .white }
        return white > 0.6 ? .black : .white
    }
    #endif

    #if os(iOS)
    private static func windowTopInset() -> CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 0
    }
    #endif
}

extension View {
    /// Puts the wordmark under the notch
    func brandPill() -> some View {
        overlay(alignment: .top) { BrandPill() }
    }
}
