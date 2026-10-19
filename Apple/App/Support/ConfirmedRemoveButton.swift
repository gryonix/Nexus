import SwiftUI

/// A trash button whose confirmation is anchored to itself
struct ConfirmedRemoveButton: View {
    let title: LocalizedStringKey
    let message: Text
    var verb: LocalizedStringKey = "Remove"
    let onConfirm: () -> Void
    @State private var isAsking = false

    var body: some View {
        Button(role: .destructive) {
            isAsking = true
        } label: {
            Label(verb, systemImage: "trash")
        }
        .dangerTint()
        .confirmationDialog(title, isPresented: $isAsking, titleVisibility: .visible) {
            Button(verb, role: .destructive, action: onConfirm)
                .dangerTint()
            Button("Cancel", role: .cancel) {}
        } message: {
            message
        }
    }
}
