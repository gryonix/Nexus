import SwiftUI

/// A dot that pulses while a connection is being made.
struct TerminalPulseDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.tint)
            .frame(width: 10, height: 10)
            .opacity(pulsing ? 1 : 0.35)
            .scaleEffect(pulsing ? 1 : 0.7)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                       value: pulsing)
            .onAppear { pulsing = !reduceMotion }
            .accessibilityHidden(true)
    }
}

/// A short sideways shake, one swing per whole step.
struct TerminalShake: GeometryEffect {
    var steps: CGFloat

    var animatableData: CGFloat {
        get { steps }
        set { steps = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(steps * .pi * 3), y: 0))
    }
}
