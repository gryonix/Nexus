import SwiftUI

/// What the bar of unapplied edits is doing
enum PendingChangesPhase: Equatable {
    case waiting
    case applying
    case done
}

/// The words of one screen's bar
struct PendingChangesText {
    let apply: LocalizedStringKey
    var note: LocalizedStringKey?
    let applying: LocalizedStringKey
    var systemImage = "arrow.clockwise"
}

/// Floating glass bar that applies or drops edits
struct PendingChangesBar: View {
    let text: PendingChangesText
    let phase: PendingChangesPhase
    let apply: () -> Void
    let revert: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            switch phase {
            case .waiting:
                actions
                if let note = text.note {
                    Text(note).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            case .applying:
                Label { Text(text.applying) } icon: { ProgressView().controlSize(.small) }
            case .done:
                Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 460)
        .aiGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Cancel", action: revert)
                .secondaryActionButtonStyle()
            Button(action: apply) {
                Label(text.apply, systemImage: text.systemImage).frame(maxWidth: .infinity)
            }
            .prominentActionButtonStyle()
        }
    }
}

private struct PendingChangesInset: ViewModifier {
    let phase: PendingChangesPhase?
    let text: PendingChangesText
    let apply: () -> Void
    let revert: () -> Void
    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let phase {
                    PendingChangesBar(text: text, phase: phase, apply: apply, revert: revert)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: phase)
    }
}

extension View {
    /// Shows the bar while edits wait or apply
    func pendingChanges(_ phase: PendingChangesPhase?, text: PendingChangesText,
                        apply: @escaping () -> Void, revert: @escaping () -> Void) -> some View {
        modifier(PendingChangesInset(phase: phase, text: text, apply: apply, revert: revert))
    }
}
