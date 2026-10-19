import SwiftUI

/// The world map with picked countries in the accent colour.
struct WorldMapView: View {
    let selected: Set<String>
    var onToggle: ((String) -> Void)?
    /// Shows the corner button for full screen
    var onExpand: (() -> Void)?
    /// Takes the whole space instead of the map's own proportions
    var fillsSpace = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var transitions: [String: MapTransition] = [:]
    @State private var viewport = MapViewport(content: WorldMap.shared.size)
    @State private var gestureBase: MapViewport?
    @State private var cardSize: CGSize = .zero
    private let map = WorldMap.shared

    var body: some View {
        TimelineView(.animation(paused: transitions.isEmpty)) { timeline in
            Canvas { context, size in
                WorldMapPainter(map: map, selected: selected, transitions: transitions,
                                now: timeline.date, viewport: viewport,
                                land: Self.landColour(colorScheme))
                    .paint(&context, size: size)
            }
        }
        .modifier(MapShape(ratio: map.size.width / map.size.height, fills: fillsSpace))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background { sizeReader }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { withAnimation(.snappy) { viewport.reset(in: cardSize) } }
        .onTapGesture(coordinateSpace: .local) { toggleCountry(at: $0) }
        .gesture(magnify(in: cardSize).simultaneously(with: drag(in: cardSize)))
        .overlay(alignment: .topTrailing) { zoomOutButton }
        .overlay(alignment: .bottomTrailing) { expandButton }
        .onChange(of: selected) { old, new in record(from: old, to: new) }
        .accessibilityElement()
        .accessibilityLabel(Text("World map"))
        .accessibilityHint(Text("Pinch the map to zoom in, drag to move, double-tap to fit it back."))
        .accessibilityValue(Text("\(selected.count) selected"))
    }

    @ViewBuilder
    private var zoomOutButton: some View {
        if viewport.isZoomedIn {
            Button {
                withAnimation(.snappy) { viewport.reset(in: cardSize) }
            } label: {
                Label("Whole world", systemImage: "arrow.down.right.and.arrow.up.left")
                    .labelStyle(.iconOnly)
                    .padding(8)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
        }
    }

    @ViewBuilder
    private var expandButton: some View {
        if let onExpand {
            Button(action: onExpand) {
                Label("Open the map full screen",
                      systemImage: "arrow.up.left.and.arrow.down.right")
                    .labelStyle(.iconOnly)
                    .padding(8)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(6)
        }
    }

    private var sizeReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { cardSize = proxy.size }
                .onChange(of: proxy.size) { _, new in cardSize = new }
        }
    }

    private func toggleCountry(at location: CGPoint) {
        let perUnit = viewport.pointsPerUnit(in: cardSize)
        guard perUnit > 0 else { return }
        if let code = map.country(at: viewport.mapPoint(for: location, in: cardSize),
                                  tolerance: 14 / perUnit) {
            onToggle?(code)
        }
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let base = started()
                let anchor = CGPoint(x: value.startAnchor.x * size.width,
                                     y: value.startAnchor.y * size.height)
                var next = base
                next.zoom(by: value.magnification, around: anchor, in: size)
                guard next != viewport else { return }
                viewport = next
            }
            .onEnded { _ in gestureBase = nil }
    }

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: canPan ? 2 : .greatestFiniteMagnitude,
                    coordinateSpace: .local)
            .onChanged { value in
                guard canPan else { return }
                var next = started()
                next.pan(by: value.translation, in: size)
                guard next != viewport else { return }
                viewport = next
            }
            .onEnded { _ in gestureBase = nil }
    }

    /// Panning only makes sense zoomed in
    private var canPan: Bool { viewport.isZoomedIn }

    private func started() -> MapViewport {
        if let gestureBase { return gestureBase }
        gestureBase = viewport
        return viewport
    }

    private func record(from old: Set<String>, to new: Set<String>) {
        guard !reduceMotion else { return }
        let now = Date()
        for (codes, isOn) in [(new.subtracting(old), true), (old.subtracting(new), false)] {
            let delays = MapTransition.staggered(codes, in: map)
            for code in codes {
                transitions[code] = MapTransition(
                    isOn: isOn, start: now.addingTimeInterval(delays[code, default: 0]))
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(MapTransition.longest))
            let later = Date()
            transitions = transitions.filter { !$0.value.isFinished(at: later) }
        }
    }
}

/// One country turning on or off
struct MapTransition {
    static let duration = 0.7
    static let maxStagger = 0.6
    static var longest: Double { duration + maxStagger + 0.1 }

    let isOn: Bool
    let start: Date

    func progress(at now: Date) -> CGFloat {
        CGFloat(min(max(now.timeIntervalSince(start) / Self.duration, 0), 1))
    }

    func isFinished(at now: Date) -> Bool { progress(at: now) >= 1 }

    /// Delays that ripple outward from the group's middle
    static func staggered(_ codes: Set<String>, in map: WorldMap) -> [String: Double] {
        let centers = codes.compactMap { code in map.countries[code].map { (code, $0.center) } }
        guard centers.count > 1 else { return [:] }
        let mid = CGPoint(x: centers.map(\.1.x).reduce(0, +) / CGFloat(centers.count),
                          y: centers.map(\.1.y).reduce(0, +) / CGFloat(centers.count))
        let distances = centers.map { ($0.0, hypot($0.1.x - mid.x, $0.1.y - mid.y)) }
        let farthest = max(distances.map(\.1).max() ?? 1, 1)
        return Dictionary(uniqueKeysWithValues: distances.map { ($0.0, Double($0.1 / farthest) * maxStagger) })
    }
}

/// Draws land, picked countries and their transitions
struct WorldMapPainter {
    let map: WorldMap
    let selected: Set<String>
    let transitions: [String: MapTransition]
    let now: Date
    var viewport: MapViewport?
    var land = WorldMapView.landColour(.light)

    private let accent = Color.accentColor

    func paint(_ context: inout GraphicsContext, size: CGSize) {
        let viewport = viewport ?? MapViewport(content: map.size)
        let scale = viewport.pointsPerUnit(in: size)
        guard scale > 0 else { return }
        context.scaleBy(x: scale, y: scale)
        let visible = viewport.visible(in: size)
        context.translateBy(x: -visible.minX, y: -visible.minY)
        let inView = visible.insetBy(dx: -1, dy: -1)
        let onScreen = map.shaped.filter { $0.value.bounds.intersects(inView) }
        let wholeWorld = !viewport.isZoomedIn
        paintLand(onScreen, whole: wholeWorld, in: &context)
        for (code, country) in onScreen {
            paintShape(code, country, in: &context, scale: scale)
        }
        strokeLand(onScreen, whole: wholeWorld, in: &context, scale: scale)
        for (code, country) in map.dots where inView.contains(country.center) {
            paintDot(code, country, in: &context, scale: scale)
        }
    }

    /// Zoomed in, only what is on screen is drawn
    private func paintLand(_ onScreen: [String: WorldMap.Country], whole: Bool,
                           in context: inout GraphicsContext) {
        guard !whole else {
            context.fill(map.land, with: .color(land))
            return
        }
        for country in onScreen.values {
            context.fill(country.shape, with: .color(land))
        }
    }

    private func strokeLand(_ onScreen: [String: WorldMap.Country], whole: Bool,
                            in context: inout GraphicsContext, scale: CGFloat) {
        let width = 0.7 / scale
        guard !whole else {
            context.stroke(map.land, with: .color(WorldMapView.plate), lineWidth: width)
            return
        }
        for country in onScreen.values {
            context.stroke(country.shape, with: .color(WorldMapView.plate), lineWidth: width)
        }
    }

    private func paintShape(_ code: String, _ country: WorldMap.Country,
                            in context: inout GraphicsContext, scale: CGFloat) {
        guard let transition = transitions[code] else {
            if selected.contains(code) { context.fill(country.shape, with: .color(accent)) }
            return
        }
        let eased = easeOut(transition.progress(at: now))
        let reach = country.reach * 1.05
        let radius = transition.isOn ? reach * eased : reach * (1 - eased)
        if radius > 0 {
            var inked = context
            inked.clip(to: Path(ellipseIn: circle(country.center, radius)))
            inked.fill(country.shape, with: .color(accent))
        }
        if transition.isOn, eased > 0, eased < 1 {
            let wave = reach * eased + 10 / scale
            context.stroke(Path(ellipseIn: circle(country.center, wave)),
                           with: .color(accent.opacity(Double(1 - eased) * 0.8)), lineWidth: 2 / scale)
        }
    }

    private func paintDot(_ code: String, _ country: WorldMap.Country,
                          in context: inout GraphicsContext, scale: CGFloat) {
        let isOn = selected.contains(code)
        guard let transition = transitions[code] else {
            let radius = (isOn ? 3 : 1.6) / scale
            context.fill(Path(ellipseIn: circle(country.center, radius)),
                         with: .color(isOn ? accent : land))
            return
        }
        let progress = transition.progress(at: now)
        let base = (transition.isOn ? 3 : 1.6 + 1.4 * (1 - progress)) / scale
        let pop = base * (1 + 1.2 * sin(.pi * progress))
        context.fill(Path(ellipseIn: circle(country.center, pop)),
                     with: .color(transition.isOn || progress < 1 ? accent : land))
        if transition.isOn, progress > 0, progress < 1 {
            context.stroke(Path(ellipseIn: circle(country.center, (4 + 14 * progress) / scale)),
                           with: .color(accent.opacity(Double(1 - progress))), lineWidth: 1.5 / scale)
        }
    }

    private func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    private func easeOut(_ t: CGFloat) -> CGFloat { 1 - pow(1 - t, 3) }
}

/// The card keeps the map's proportions; full screen takes everything
private struct MapShape: ViewModifier {
    let ratio: CGFloat
    let fills: Bool

    func body(content: Content) -> some View {
        if fills {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content.aspectRatio(ratio, contentMode: .fit)
        }
    }
}

extension WorldMapView {
    /// Unpicked land, lighter in the dark
    static func landColour(_ scheme: ColorScheme) -> Color {
        Color.primary.opacity(scheme == .dark ? 0.3 : 0.14)
    }

    #if os(iOS)
    static let plate = Color(.secondarySystemGroupedBackground)
    static let pageBackground = Color(.systemGroupedBackground)
    #else
    static let plate = Color(nsColor: .controlBackgroundColor)
    static let pageBackground = Color(nsColor: .windowBackgroundColor)
    #endif
}
