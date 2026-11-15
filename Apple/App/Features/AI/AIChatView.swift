import AIAssistant
import SwiftUI

/// One AI conversation: bubbles, typing dots and a floating input
struct AIChatView: View {
    let chatID: String
    @ObservedObject private var store = AIChatStore.shared
    @ObservedObject private var settings = AISettings.shared
    @State private var draft = ""
    @State private var attachments: [Data] = []

    private var chat: AIChat? { store.chat(chatID) }
    private var messages: [AIChatMessage] { chat?.messages ?? [] }
    private var isStreaming: Bool { store.streamingChatID == chatID }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if messages.isEmpty {
                    AIChatWelcome { send($0) }
                } else {
                    thread
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.last?.text) { scrollToEnd(proxy) }
            .onChange(of: isStreaming) { scrollToEnd(proxy) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AIChatInputBar(draft: $draft, attachments: $attachments, canAttach: !settings.isOnDevice,
                           isStreaming: isStreaming, onSend: { send(draft) }, onStop: { store.stop() })
        }
        .background(AIChatBackdrop())
        .screenTitle(chat?.title ?? "")
    }

    private var thread: some View {
        LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(messages) { message in
                AIMessageBubble(message: message, showsTokens: !settings.isLocal,
                                canRegenerate: canRegenerate(message),
                                regenerate: { store.regenerate(chatID) })
            }
            if isStreaming && messages.last?.role != .assistant {
                AITypingBubble()
            }
            AIChatBanner(failure: store.failure, budget: settings.budget)
            Color.clear.frame(height: 1).id("end")
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("end", anchor: .bottom) }
    }

    private func canRegenerate(_ message: AIChatMessage) -> Bool {
        !isStreaming && message.role == .assistant && message.id == messages.last?.id
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty, !isStreaming else { return }
        let images = attachments
        draft = ""
        attachments = []
        store.send(trimmed, images: images, in: chatID)
    }
}

/// Failure and token-limit notices under the thread
private struct AIChatBanner: View {
    let failure: String?
    let budget: AIBudgetState

    var body: some View {
        if let failure {
            notice(Text(verbatim: failure), systemImage: "exclamationmark.triangle.fill")
        }
        if budget == .nearLimit || budget == .reached {
            notice(Text(budget == .reached
                        ? "The monthly token limit is reached."
                        : "Close to the monthly token limit."),
                   systemImage: "gauge.with.dots.needle.67percent")
        }
    }

    private func notice(_ text: Text, systemImage: String) -> some View {
        Label { text } icon: { Image(systemName: systemImage) }
            .font(.footnote)
            .foregroundStyle(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Soft colour wash the glass bubbles float over
private struct AIChatBackdrop: View {
    var body: some View {
        ZStack {
            Color.aiChatBackground
            LinearGradient(colors: [Color.accentColor.opacity(0.14), .clear, Color.purple.opacity(0.10)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .ignoresSafeArea()
    }
}

extension Color {
    /// Chat backdrop under the colour wash
    static var aiChatBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.clear
        #endif
    }
}
