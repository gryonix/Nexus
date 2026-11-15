import AIAssistant
import SwiftUI

struct AIMarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let value): inline(value)
        case .heading(_, let value): inline(value).font(.headline)
        case .quote(let value): inline(value).foregroundStyle(.secondary)
        case .bullets(let items): list(items) { _ in "•" }
        case .numbered(let items): list(items) { "\($0 + 1)." }
        case .code(_, let value): AICodeBlock(code: value)
        }
    }

    private func list(_ items: [String], marker: @escaping (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: marker(index))
                    inline(item)
                }
            }
        }
    }

    private func inline(_ value: String) -> some View {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let attributed = (try? AttributedString(markdown: value, options: options)) ?? AttributedString(value)
        return Text(attributed)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A suggested command: copy it, never run it.
struct AICodeBlock: View {
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(verbatim: code)
                    .font(.system(.footnote, design: .monospaced))
                    .fixedSize()
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Text("Check before you run it — the AI can be wrong.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    AIClipboard.copy(code)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

enum AIClipboard {
    static func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = string
        #endif
    }
}
