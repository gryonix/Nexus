import AIAssistant
import ServiceCatalog
import SwiftTerm
import SwiftUI

/// "Ask AI" in the terminal; answers can only be copied.
@available(macOS 15.0, *)
struct AITerminalMenu: View {
    @ObservedObject var controller: TerminalController
    let serverName: String
    @ObservedObject private var modules = ModuleSettings.shared
    @State private var describing = false
    @State private var need = ""

    var body: some View {
        if modules.isOn(.ai) {
            Menu {
                Button { explain() } label: { Label("Explain this command", systemImage: "questionmark.bubble") }
                Button { describing = true } label: { Label("Describe what you need", systemImage: "text.bubble") }
            } label: {
                Label("Ask AI", systemImage: "sparkles")
            }
            .sheet(isPresented: $describing) { askSheet }
        }
    }

    private var askSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What do you want to do?", text: $need, axis: .vertical).lineLimit(2...6)
                } footer: {
                    Text("Suggested commands can only be copied. Nothing is typed into the terminal.")
                }
            }
            .screenTitle("Describe what you need")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { describing = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ask") { ask() }.disabled(need.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func explain() {
        let text = TerminalTextSource.selectionOrTail(controller.view)
        AIChatStore.shared.start(AIContext(kind: .terminalExplain, title: UIL10n.string("Terminal on %@", serverName),
                                           sections: [("Terminal", text)]))
    }

    private func ask() {
        let request = need.trimmingCharacters(in: .whitespacesAndNewlines)
        describing = false
        need = ""
        AIChatStore.shared.start(AIContext(kind: .terminalAsk, title: UIL10n.string("Terminal on %@", serverName),
                                           sections: [("Need", request)]))
    }
}

enum TerminalTextSource {
    static let tailLines = 30

    static func selectionOrTail(_ view: SwiftTerm.TerminalView?) -> String {
        guard let view else { return "" }
        if let selected = view.getSelection(), !selected.isEmpty { return selected }
        let data = view.getTerminal().getBufferAsData()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
        return lines.suffix(tailLines).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }
}
