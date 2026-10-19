#if os(iOS)
import SwiftUI

/// Everything but the spotlights
private struct DimmedArea: Shape {
    let cutouts: [CGRect]

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addRect(rect)
            for cutout in cutouts {
                let radius = AppTourOverlay.corner(for: cutout)
                path.addRoundedRect(in: cutout, cornerSize: CGSize(width: radius, height: radius))
            }
        }
    }
}

/// Dims the app, spotlights the step's target and explains it.
struct AppTourOverlay: View {
    @ObservedObject var tour: AppTour
    let onConfigure: () -> Void

    @ObservedObject private var bars = TabBarSettings.shared
    @State private var pulse = false
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var barLayoutTick = 0

    var body: some View {
        GeometryReader { proxy in
            if let step = tour.step {
                let _ = barLayoutTick
                let arriving = tour.arriving == step
                let spots = arriving ? [] : spotlightRects(for: step, in: proxy)
                let spotlight = spots.dropFirst().reduce(spots.first) { $0?.union($1) }
                ZStack {
                    dimming(cutouts: spots, tryable: step.isStyleChoice, in: proxy.size)
                    ForEach(Array(spots.enumerated()), id: \.offset) { glow(around: $0.element) }
                    if !arriving {
                        placedCard(for: step, room: cardRoom(around: spotlight, in: proxy))
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.86), value: step)
                .animation(.spring(response: 0.45, dampingFraction: 0.86), value: spots)
                .animation(.easeOut(duration: 0.25), value: arriving)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: tour.step == nil)
        .task(id: bars.barStyle) {
            for delay in [150, 400, 900] {
                try? await Task.sleep(for: .milliseconds(delay))
                barLayoutTick += 1
            }
        }
    }

    private func spotlightRects(for step: AppTourStep, in proxy: GeometryProxy) -> [CGRect] {
        guard let target = step.target else { return [] }
        let origin = proxy.frame(in: .global).origin
        let cap = proxy.size.height * (textSize.isAccessibilitySize ? 0.2 : 0.34)
        let live = target == .sectionBar ? Self.liveBarFrame() : nil
        var raws = [live ?? tour.frames[target]].compactMap { $0 }
        if Self.insideServer.contains(target), let frame = raws.first {
            let cards = VisibleListScroller.cardFrames(around: frame, maxHeight: cap)
            if !cards.isEmpty { raws = cards }
        }
        let ceiling = contentCeiling(for: target, origin: origin) ?? proxy.safeAreaInsets.top
        let screen = CGRect(origin: .zero, size: proxy.size)
            .inset(by: UIEdgeInsets(top: ceiling, left: 6, bottom: 6, right: 6))
        return raws.compactMap { raw in
            var fitted = raw.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -4, dy: -4).intersection(screen)
            guard !fitted.isNull, fitted.height > 8 else { return nil }
            fitted.size.height = min(fitted.height, cap + 8)
            return fitted
        }
    }

    private static let insideServer: Set<AppTourTarget> = [.serverSites, .serverApps, .serverMetrics, .serverSecurity]

    /// Server content scrolls under the strip, so it ends there
    private func contentCeiling(for target: AppTourTarget, origin: CGPoint) -> CGFloat? {
        guard Self.insideServer.contains(target), let strip = tour.frames[.serverStrip] else { return nil }
        return strip.maxY - origin.y + 4
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    /// The bottom bar on screen right now
    private static func liveBarFrame() -> CGRect? {
        guard let window = keyWindow else { return nil }
        if let strip = view(identified: "shell.sections", in: window) {
            return strip.convert(strip.bounds, to: window)
        }
        return systemTabBarFrame(in: window)
    }

    private static func view(identified identifier: String, in root: UIView) -> UIView? {
        if root.accessibilityIdentifier == identifier, root.window != nil, !root.isHidden,
           root.alpha > 0.01, root.bounds.width > 1 {
            return root
        }
        for child in root.subviews {
            if let found = view(identified: identifier, in: child) { return found }
        }
        return nil
    }

    /// The system tab bar's frame in window coordinates
    private static func systemTabBarFrame(in window: UIWindow) -> CGRect? {
        guard let bar = tabBar(in: window), !bar.isHidden else { return nil }
        let buttons = controls(in: bar).map { $0.convert($0.bounds, to: window) }
        guard let first = buttons.first else { return bar.convert(bar.bounds, to: window) }
        return buttons.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -8, dy: -4)
    }

    /// The bar's own buttons, which the visible capsule wraps
    private static func controls(in view: UIView) -> [UIControl] {
        view.subviews.flatMap { child -> [UIControl] in
            if let control = child as? UIControl, !control.isHidden, control.bounds.width > 1 {
                return [control]
            }
            return controls(in: child)
        }
    }

    private static func tabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        for child in view.subviews {
            if let bar = tabBar(in: child) { return bar }
        }
        return nil
    }

    static func corner(for rect: CGRect) -> CGFloat {
        rect.height <= 80 ? rect.height / 2 : 30
    }

    /// On a style step the spotlight stays tappable
    private func dimming(cutouts: [CGRect], tryable: Bool, in size: CGSize) -> some View {
        let shape = DimmedArea(cutouts: cutouts)
        return shape
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .contentShape(tryable ? AnyShape(shape) : AnyShape(Rectangle()), eoFill: tryable)
            .onTapGesture {}
    }

    private func glow(around rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: Self.corner(for: rect), style: .continuous)
            .stroke(Color.accentColor, lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .opacity(pulse ? 0.35 : 1)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            }
    }

    /// Puts the card on the roomier side of the spotlight
    private func cardRoom(around spotlight: CGRect?, in proxy: GeometryProxy)
        -> (alignment: Alignment, top: CGFloat, bottom: CGFloat) {
        let top = proxy.safeAreaInsets.top + 12
        let bottom = proxy.safeAreaInsets.bottom + 12
        guard let spotlight else { return (.center, top, bottom) }
        let above = spotlight.minY - top
        let below = proxy.size.height - bottom - spotlight.maxY
        if above >= below {
            return (.bottom, top, proxy.size.height - spotlight.minY + 16)
        }
        return (.top, spotlight.maxY + 16, bottom + 64)
    }

    private func placedCard(for step: AppTourStep,
                            room: (alignment: Alignment, top: CGFloat, bottom: CGFloat)) -> some View {
        card(for: step)
            .frame(maxWidth: 440)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: room.alignment)
            .padding(.top, room.top)
            .padding(.bottom, room.bottom)
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
    }

    private func card(for step: AppTourStep) -> some View {
        AppTourCard(step: step, bars: bars,
                    onBack: { tour.back() },
                    onNext: { tour.next() },
                    onSkip: { tour.finish() },
                    onConfigure: {
                        tour.finish()
                        onConfigure()
                    })
    }
}

#endif
