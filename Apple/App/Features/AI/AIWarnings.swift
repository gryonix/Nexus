import AIAssistant
import SwiftUI

/// Shown once when the module is first turned on.
struct AIModuleAgreementSheet: View {
    let onAgree: () -> Void
    let onCancel: () -> Void

    var body: some View {
        AINoticeSheet(icon: "exclamationmark.bubble",
                      title: "The AI can be wrong",
                      message: "The AI can be wrong. It only advises and never changes your servers. You decide and act.",
                      actionTitle: "Agree", action: onAgree, onCancel: onCancel)
    }
}

/// Lists what a cloud provider receives, with a redacted example.
struct AICloudNoticeSheet: View {
    let providerName: String
    let onAgree: () -> Void
    let onCancel: () -> Void
    @State private var showingExample = false

    var body: some View {
        AINoticeSheet(icon: "icloud.and.arrow.up",
                      title: "What is sent to \(providerName)",
                      message: "When you ask, the app sends your question and the logs and metrics it picked for it to \(providerName). Passwords, tokens, keys and other secrets are removed first.",
                      actionTitle: "Agree", action: onAgree, onCancel: onCancel) {
            Button("Show an example") { showingExample.toggle() }
            if showingExample {
                Text(verbatim: Self.example)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    static var example: String {
        AIPrompts.contextMessage(AIContext(
            kind: .service, title: "web",
            sections: [("Logs", "starting web\nDB_PASSWORD=hunter2hunter2\nAuthorization: Bearer abc123def456\nerror: connection refused")]))
    }
}

struct AILocalNoticeSheet: View {
    let onAgree: () -> Void
    let onCancel: () -> Void

    var body: some View {
        AINoticeSheet(icon: "house",
                      title: "Your data stays at home",
                      message: "Questions and logs go to your own Ollama service. Nothing is sent to a cloud provider.",
                      actionTitle: "OK", action: onAgree, onCancel: onCancel)
    }
}

struct AINoticeSheet<Extra: View>: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    let action: () -> Void
    let onCancel: () -> Void
    @ViewBuilder var extra: Extra

    init(icon: String, title: LocalizedStringKey, message: LocalizedStringKey,
         actionTitle: LocalizedStringKey, action: @escaping () -> Void, onCancel: @escaping () -> Void,
         @ViewBuilder extra: () -> Extra = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.onCancel = onCancel
        self.extra = extra()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: icon).font(.largeTitle).foregroundStyle(.tint)
                    Text(title).font(.title2.weight(.semibold))
                    Text(message)
                    extra
                    Button(action: action) { Text(actionTitle).frame(maxWidth: .infinity) }
                        .prominentActionButtonStyle()
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }
}
