import SwiftUI

/// A text row whose edit waits in the bar
struct PendingTextRow: View {
    let id: String
    let title: LocalizedStringKey
    let prompt: String
    let saved: String
    let edits: PendingRowEdits
    var text: PendingChangesText = .save
    var spokenName = true
    var clearsAfterApply = false
    var valid: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    let apply: @MainActor (String) async -> Bool
    @State private var draft: String

    init(id: String, title: LocalizedStringKey, prompt: String, saved: String, edits: PendingRowEdits,
         text: PendingChangesText = .save, spokenName: Bool = true, clearsAfterApply: Bool = false, valid: @escaping (String) -> Bool = { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
         apply: @escaping @MainActor (String) async -> Bool) {
        self.id = id
        self.title = title
        self.prompt = prompt
        self.saved = saved
        self.edits = edits
        self.text = text
        self.spokenName = spokenName
        self.clearsAfterApply = clearsAfterApply
        self.valid = valid
        self.apply = apply
        _draft = State(initialValue: saved)
    }

    var body: some View {
        TechnicalField(title: title, prompt: prompt, text: $draft, spokenName: spokenName)
            .onChange(of: draft) { offerEdit() }
            .onChange(of: saved) { draft = saved }
    }

    private func offerEdit() {
        let field = $draft
        let saved = saved
        let edit = PendingRowEdits.Edit(
            id: id, text: text,
            apply: { [apply, clearsAfterApply] in
                let done = await apply(field.wrappedValue)
                if done && clearsAfterApply { field.wrappedValue = saved }
                return done
            },
            revert: { field.wrappedValue = saved })
        edits.offer(edit, changed: draft != saved && valid(draft))
    }
}
