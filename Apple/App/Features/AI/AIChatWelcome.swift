import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Empty chat: greeting and ready-made questions
struct AIChatWelcome: View {
    let ask: (String) -> Void

    private static let suggestions = [
        "Why might a server be unreachable?",
        "What takes up the most disk space?",
        "Which services need attention?",
        "How do I make my servers safer?",
    ]

    var body: some View {
        VStack(spacing: 14) {
            AIAvatar(size: 56)
                .padding(.top, 48)
            Text("How can I help?")
                .font(.title2.weight(.semibold))
            Text("I suggest what to do on your servers. I never run anything myself.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion($0) }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }

    private func suggestion(_ key: String) -> some View {
        Button { ask(UIL10n.string(key)) } label: {
            Text(LocalizedStringKey(key))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .aiGlass(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension AIClipboard {
    static var hasImage: Bool {
        #if os(iOS)
        UIPasteboard.general.hasImages
        #elseif os(macOS)
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self])
        #else
        false
        #endif
    }

    /// The clipboard's picture as image data
    static func imageData() -> Data? {
        #if os(iOS)
        UIPasteboard.general.image?.pngData()
        #elseif os(macOS)
        (NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first?.tiffRepresentation
        #else
        nil
        #endif
    }
}
