import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor
enum Haptics {
    static let settingKey = "haptics.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    /// What a moment feels like
    enum Feel: Equatable {
        /// An ordinary button
        case tap
        /// A button that destroys something
        case weighty
        /// An operation finished, or refused
        case success
        case failure
    }

    /// What a button's role feels like
    static func feel(forRole role: ButtonRole?) -> Feel {
        role == .destructive ? .weighty : .tap
    }

    static func play(_ feel: Feel) {
        guard isEnabled else { return }
        #if os(iOS)
        switch feel {
        case .tap:
            impact(.light).impactOccurred()
        case .weighty:
            impact(.rigid).impactOccurred()
        case .success:
            notifier.notificationOccurred(.success)
        case .failure:
            notifier.notificationOccurred(.error)
        }
        #elseif os(macOS)
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch feel {
        case .tap, .success: pattern = .generic
        case .weighty, .failure: pattern = .levelChange
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        #endif
    }

    #if os(iOS)
    private static var generators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private static let notifier = UINotificationFeedbackGenerator()

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        if let existing = generators[style] {
            defer { existing.prepare() }
            return existing
        }
        let generator = UIImpactFeedbackGenerator(style: style)
        generators[style] = generator
        generator.prepare()
        return generator
    }
    #endif
}

/// The one place a press becomes a buzz
struct HapticButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HapticButton(configuration: configuration)
    }
}

private struct HapticButton: View {
    let configuration: PrimitiveButtonStyleConfiguration

    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(role: configuration.role) {
            Haptics.play(Haptics.feel(forRole: configuration.role))
            configuration.trigger()
        } label: {
            configuration.label
        }
        .buttonStyle(.automatic)
        .scaleEffect(isPressed && !reduceMotion ? 0.96 : 1)
        .opacity(isPressed ? 0.75 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let moved = max(abs(value.translation.width),
                                    abs(value.translation.height))
                    isPressed = moved < 10
                }
                .onEnded { _ in isPressed = false }
        )
    }
}
