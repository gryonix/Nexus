import SwiftUI

/// Toolbar back: one step back, else leaves the screen
struct WizardBackButton: View {
    /// Steps back; false when already on the first step
    let stepBack: () -> Bool
    var onLeave: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            if stepBack() { return }
            if let onLeave { onLeave() } else { dismiss() }
        } label: {
            Label("Back", systemImage: "chevron.left")
        }
        .accessibilityIdentifier("wizard.back")
    }
}
