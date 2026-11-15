import AIAssistant
import SwiftUI

/// A user or assistant message bubble
struct AIMessageBubble: View {
    let message: AIChatMessage
    let showsTokens: Bool
    let canRegenerate: Bool
    let regenerate: () -> Void

    var body: some View {
        if message.role == .user { userBubble } else { assistantBubble }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 6) {
                if let ids = message.imageIDs, !ids.isEmpty {
                    AIMessageImages(ids: ids)
                }
                if !message.text.isEmpty {
                    Text(verbatim: message.text)
                        .font(.body)
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .aiGlass(AIBubbleShape(fromUser: true), tint: .accentColor)
                }
            }
        }
    }

    private var assistantBubble: some View {
        HStack(alignment: .top, spacing: 10) {
            AIAvatar()
            VStack(alignment: .leading, spacing: 6) {
                AIMarkdownView(text: message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .aiGlass(AIBubbleShape(fromUser: false))
                AIMessageActions(message: message, showsTokens: showsTokens,
                                 canRegenerate: canRegenerate, regenerate: regenerate)
            }
            Spacer(minLength: 24)
        }
    }
}

/// Copy, regenerate and token count under an answer
private struct AIMessageActions: View {
    let message: AIChatMessage
    let showsTokens: Bool
    let canRegenerate: Bool
    let regenerate: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 14) {
            Button {
                AIClipboard.copy(message.text)
                copied = true
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .accessibilityLabel(Text("Copy"))
            if canRegenerate {
                Button(action: regenerate) { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel(Text("Regenerate"))
            }
            if showsTokens, let input = message.inputTokens, let output = message.outputTokens {
                Text("\(input + output) tokens")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .buttonStyle(.borderless)
        .padding(.leading, 6)
    }
}

/// Round sparkle badge beside the assistant's messages
struct AIAvatar: View {
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [.accentColor, .purple],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle())
            .accessibilityHidden(true)
    }
}

/// Three pulsing dots while the answer is on its way
struct AITypingBubble: View {
    @State private var phase = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AIAvatar()
            HStack(spacing: 5) {
                ForEach(0..<3) { index in
                    Circle()
                        .frame(width: 7, height: 7)
                        .opacity(phase ? 1 : 0.3)
                        .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2),
                                   value: phase)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .aiGlass(AIBubbleShape(fromUser: false))
        }
        .onAppear { phase = true }
        .accessibilityLabel(Text("Writing an answer"))
    }
}

/// Pictures the user sent, as rounded thumbnails
private struct AIMessageImages: View {
    let ids: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ids, id: \.self) { id in
                if let data = AIImageStore.data(id), let image = AIImageStore.image(data) {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: ids.count == 1 ? 200 : 96, height: ids.count == 1 ? 200 : 96)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }
}

/// Rounded bubble with a tighter corner toward its sender
struct AIBubbleShape: Shape {
    let fromUser: Bool

    func path(in rect: CGRect) -> Path {
        let big: CGFloat = 18
        let small: CGFloat = 6
        let radii = RectangleCornerRadii(topLeading: fromUser ? big : small,
                                         bottomLeading: big,
                                         bottomTrailing: big,
                                         topTrailing: fromUser ? small : big)
        return UnevenRoundedRectangle(cornerRadii: radii).path(in: rect)
    }
}

extension Color {
    /// Assistant bubble fill
    static var aiBubble: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.secondary.opacity(0.15)
        #endif
    }
}
