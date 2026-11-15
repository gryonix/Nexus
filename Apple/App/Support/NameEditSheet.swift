import SwiftUI

/// A sheet with one name row
struct NameEditSheet: View {
    let title: LocalizedStringKey
    let fieldTitle: LocalizedStringKey
    let initial: String
    var confirm: PendingChangesText = .save
    var valid: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    let onSave: (String) -> Void
    @StateObject private var edits = PendingRowEdits()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CardList {
                Section {
                    PendingTextRow(id: "name-sheet", title: fieldTitle, prompt: initial, saved: initial,
                                   edits: edits, text: confirm, valid: valid) { name in
                        onSave(name)
                        dismiss()
                        return true
                    }
                }
            }
            .screenTitle(title)
            .pendingRowEdits(edits)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .phoneSheetDetents([.medium])
    }
}
