import SwiftUI

/// A tapped alert with its advice, over the server
struct AlertCardSheet: View {
    let card: AlertCard
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: card.title).font(.headline)
                    if !card.body.isEmpty { Text(verbatim: card.body).textSelection(.enabled) }
                }
                if let advice = card.advice {
                    Section { adviceRows(advice) }
                }
            }
            .formStyle(.grouped)
            .screenTitle("Error")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private func adviceRows(_ advice: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("What to do", systemImage: "lightbulb")
                .font(.callout.weight(.semibold))
            Text(verbatim: advice)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
