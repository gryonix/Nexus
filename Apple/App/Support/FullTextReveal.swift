import SwiftUI
#if os(iOS)
import UIKit
#endif

extension View {
    func revealsFullText(_ text: String) -> some View {
        modifier(FullTextReveal(text: Text(verbatim: text), copyable: text))
    }

    func revealsFullText(_ key: LocalizedStringKey) -> some View {
        modifier(FullTextReveal(text: Text(key), copyable: nil))
    }
}

private struct FullTextReveal: ViewModifier {
    let text: Text
    let copyable: String?

    func body(content: Content) -> some View {
        #if os(macOS)
        content.help(text)
        #else
        content.contextMenu {
            if let copyable {
                Button {
                    UIPasteboard.general.string = copyable
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            } else {
                text
            }
        } preview: {
            text
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320, alignment: .leading)
                .padding(16)
        }
        #endif
    }
}
