#if os(macOS)
import SwiftUI

/// A tour step as a popover on its target
struct AppTourPopover: ViewModifier {
    let target: AppTourTarget
    let part: UUID
    @ObservedObject private var tour = AppTour.shared

    private var shownStep: AppTourStep? {
        guard let step = tour.step, step.target == target, tour.arriving != step,
              tour.anchors[target] == part else { return nil }
        return step
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if shownStep != nil { AppTourRing() }
            }
            .popover(isPresented: .constant(shownStep != nil), arrowEdge: arrowEdge) {
                if let step = shownStep {
                    AppTourMacCard(step: step, framed: false)
                        .frame(width: 380)
                        .interactiveDismissDisabled()
                }
            }
    }

    private var arrowEdge: Edge {
        target == .sectionBar ? .trailing : .bottom
    }
}

/// The accent frame around what a step talks about
private struct AppTourRing: View {
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.accentColor, lineWidth: 2)
            .padding(-3)
            .opacity(pulse ? 0.35 : 1)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
            }
    }
}

/// Steps with nothing to point at, floating over the window
struct AppTourMacOverlay: View {
    @ObservedObject var tour: AppTour

    private var floatingStep: AppTourStep? {
        guard let step = tour.step, tour.arriving != step else { return nil }
        guard let target = step.target else { return step }
        return tour.anchors[target] == nil ? step : nil
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if let step = floatingStep {
                AppTourMacCard(step: step, framed: true)
                    .frame(maxWidth: 440)
                    .padding(24)
                    .id(step)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: floatingStep)
    }
}

/// The shared card, wired to the tour
private struct AppTourMacCard: View {
    let step: AppTourStep
    let framed: Bool

    var body: some View {
        AppTourCard(step: step, bars: TabBarSettings.shared,
                    onBack: { AppTour.shared.back() },
                    onNext: { AppTour.shared.next() },
                    onSkip: { AppTour.shared.finish() },
                    onConfigure: {
                        AppTour.shared.finish()
                        AppNavigator.shared.requestedTab = .configurator
                    },
                    framed: framed)
    }
}
#endif
