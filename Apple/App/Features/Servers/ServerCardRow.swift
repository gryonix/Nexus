import ServerControl
import SwiftUI

/// One row of the list
struct ServerCardsRow<Content: View>: View {
    let columns: [[ServerCardsRow.Member]]

    /// Every card in the row
    private var members: [Member] { columns.flatMap { $0 } }
    @ViewBuilder let content: () -> Content

    struct Member: Equatable {
        let id: UUID
        let compact: Bool
        let width: CGFloat?
    }

    var body: some View {
        content()
            .rowResizeProbeIfDebug(members.first?.id)
    }
}

struct ServerCardRow: View {
    let deployment: Deployment
    @ObservedObject var metrics: ServerCardMetrics
    var compact = false
    var width: CGFloat?
    var onWidthArrived: (() -> Void)? = nil
    @State private var drawn: CGFloat?
    @Environment(\.glassCardFloating) private var floating

    private static let liftedShadowRoom: CGFloat = 200

    @State private var settled: [Bool: CGFloat] = [:]
    @State private var pinned: CGFloat?
    @State private var floor: CGFloat = 0

    private var layoutWidth: CGFloat? {
        guard let width else { return drawn }
        guard let drawn else { return width }
        return max(width, drawn)
    }

    private var alternateWidth: CGFloat? {
        guard let width, width > 0 else { return nil }
        let gutter = ServerListView.columnGutter
        return compact ? width * 2 + gutter : max(0, (width - gutter) / 2)
    }

    var body: some View {
        card
            .frame(width: layoutWidth, alignment: .leading)
            .animation(.snappy(duration: Self.slide), value: compact)
            .frame(width: drawn, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: GlassCardSurface.defaultCornerRadius,
                                        style: .continuous)
                .inset(by: floating ? -Self.liftedShadowRoom : 0))
            .onChange(of: width, initial: true) { _, new in
                guard drawn != nil else { drawn = new; return }
                withAnimation(.snappy(duration: Self.slide)) { drawn = new } completion: {
                    onWidthArrived?()
                }
            }
            .frame(minHeight: floor, alignment: .top)
            .frame(height: pinned, alignment: .top)
            .background(heightProbe)
            .onChange(of: compact) { was, now in
                guard let from = settled[was] else { return }
                guard let to = settled[now], to != from else {
                    floor = from
                    withAnimation(.snappy(duration: Self.slide)) { floor = 0 }
                    return
                }
                pinned = from
                DispatchQueue.main.async {
                    withAnimation(.snappy(duration: Self.slide)) {
                        pinned = to
                    } completion: {
                        pinned = nil
                    }
                }
            }
            .cardResizeProbeIfDebug(deployment.name)
    }

    private static let crossfade = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeIn(duration: 0.22 * slowdown).delay(0.04 * slowdown)),
        removal: .opacity.animation(.easeOut(duration: 0.1 * slowdown)))

    /// How long the width takes to travel, either way
    #if os(macOS)
    static let slide: Double = 0.42 * slowdown
    #else
    static let slide: Double = 0.3 * slowdown
    #endif

    /// 1 in the shipped app
    private static var slowdown: Double {
        #if DEBUG
        CardResizeProbe.slowFactor
        #else
        1
        #endif
    }

    @ViewBuilder
    private var heightProbe: some View {
        if let width, width > 0, let other = alternateWidth {
            ZStack {
                if settled[compact] == nil {
                    measuringCopy(compact: compact, at: width)
                }
                if settled[!compact] == nil {
                    measuringCopy(compact: !compact, at: other)
                }
            }
            .hidden()
            .allowsHitTesting(false)
        }
    }

    private func measuringCopy(compact shape: Bool, at width: CGFloat) -> some View {
        cardBody(compact: shape)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                guard height > 0 else { return }
                settled[shape] = height
            }
    }

    @ViewBuilder
    private var card: some View {
        cardBody(compact: compact)
    }

    /// The card itself for a given shape
    @ViewBuilder
    private func cardBody(compact: Bool) -> some View {
        let hosts = deployment.nodes.map(\.sshHost)
        if hosts.count > 1 {
            let machines = hosts.map { ($0, metrics.state(for: $0)) }
            if compact {
                CompactCombinedServerCard(deployment: deployment, machines: machines)
                    .equatable()
                    .transition(Self.crossfade)
            } else {
                CombinedServerCard(deployment: deployment, machines: machines)
                    .equatable()
                    .transition(Self.crossfade)
            }
        } else {
            let host = hosts.first ?? .vps
            if compact {
                CompactServerCard(deployment: deployment, host: host,
                                  state: metrics.state(for: host))
                    .equatable()
                    .transition(Self.crossfade)
            } else {
                ServerMetricsCard(deployment: deployment, host: host,
                                  state: metrics.state(for: host))
                    .equatable()
                    .transition(Self.crossfade)
            }
        }
    }
}

extension View {
    @ViewBuilder
    func rowResizeProbeIfDebug(_ id: UUID?) -> some View {
        #if DEBUG
        cardResizeProbe("row-\(id?.uuidString.suffix(4) ?? "?")")
        #else
        self
        #endif
    }
}

private extension View {
    @ViewBuilder
    func cardResizeProbeIfDebug(_ name: String) -> some View {
        #if DEBUG
        cardResizeProbe(name)
        #else
        self
        #endif
    }
}
