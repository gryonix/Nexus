import SwiftUI

/// One row's unapplied edit, shown in the screen's bar
@MainActor
final class PendingRowEdits: ObservableObject {
    struct Edit {
        let id: String
        let text: PendingChangesText
        let apply: @MainActor () async -> Bool
        let revert: @MainActor () -> Void
    }

    @Published private(set) var edits: [Edit] = []
    @Published private(set) var phase: PendingChangesPhase?

    /// The words of the row edited last
    var text: PendingChangesText? { edits.last?.text }

    /// A row says whether its edit waits
    func offer(_ offered: Edit, changed: Bool) {
        guard phase != .applying else { return }
        edits.removeAll { $0.id == offered.id }
        if changed { edits.append(offered) }
        phase = edits.isEmpty ? nil : .waiting
    }

    func revert() {
        let waiting = edits
        clear()
        waiting.forEach { $0.revert() }
    }

    func apply() {
        guard !edits.isEmpty, phase == .waiting else { return }
        phase = .applying
        Task {
            await applyAll()
            guard phase == .done else { return }
            try? await Task.sleep(for: .seconds(1.5))
            clear()
        }
    }

    /// Applies each edit; failed ones keep waiting
    private func applyAll() async {
        var failed: [Edit] = []
        for edit in edits {
            if await !edit.apply() { failed.append(edit) }
        }
        edits = failed
        phase = failed.isEmpty ? .done : .waiting
    }

    private func clear() {
        edits = []
        phase = nil
    }
}

extension PendingChangesText {
    static let speaker = PendingChangesText(
        apply: "Restart the speaker",
        note: "The speaker goes silent for a few seconds.",
        applying: "Restarting the speaker…")

    static let save = PendingChangesText(apply: "Save", applying: "Saving…", systemImage: "checkmark.circle")

    static let apply = PendingChangesText(apply: "Apply", applying: "Saving…", systemImage: "checkmark.circle")

    static let schedule = PendingChangesText(apply: "Save schedule", applying: "Saving…", systemImage: "checkmark.circle")

    static let mods = PendingChangesText(apply: "Apply to the server", applying: "Saving…",
                                         systemImage: "arrow.down.circle")

    static let screen = PendingChangesText(
        apply: "Restart the screen",
        note: "The screen disconnects for a few seconds.",
        applying: "Restarting the screen…")
}

private struct PendingRowEditsBar: ViewModifier {
    @ObservedObject var edits: PendingRowEdits

    func body(content: Content) -> some View {
        content.pendingChanges(edits.phase, text: edits.text ?? .speaker,
                               apply: { edits.apply() }, revert: { edits.revert() })
    }
}

extension View {
    /// Shows the bar for edits made in rows
    func pendingRowEdits(_ edits: PendingRowEdits) -> some View {
        modifier(PendingRowEditsBar(edits: edits))
    }
}
