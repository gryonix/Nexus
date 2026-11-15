import AIAssistant
import Foundation
import ServerControl

/// Chats of this device and the one answer streaming now.
@MainActor
final class AIChatStore: ObservableObject {
    static let shared = AIChatStore()

    @Published private(set) var history = AIChatHistory()
    @Published private(set) var streamingChatID: String?
    @Published var failure: String?
    @Published var openChatID: String?

    private let fileStore: AIChatFileStore
    private var task: Task<Void, Never>?

    init(fileStore: AIChatFileStore = AIChatFileStore(url: AIChatStore.defaultURL)) {
        self.fileStore = fileStore
        history = fileStore.load()
    }

    nonisolated static var defaultURL: URL {
        AppSupportDirectory.base.appendingPathComponent("gryonixNexus/ai-chats.json")
    }

    func chat(_ id: String) -> AIChat? { history.chats.first { $0.id == id } }

    func delete(_ id: String) {
        if streamingChatID == id { stop() }
        AIImageStore.delete(chat(id)?.messages.flatMap { $0.imageIDs ?? [] } ?? [])
        history.delete(id: id)
        fileStore.save(history)
    }

    func newChat(title: String, firstMessage: String? = nil) -> String {
        var chat = AIChat(title: title)
        if let firstMessage { chat.messages.append(AIChatMessage(role: .user, text: firstMessage)) }
        history.upsert(chat)
        fileStore.save(history)
        return chat.id
    }

    func start(_ context: AIContext) {
        let chatID = newChat(title: context.title, firstMessage: AIPrompts.contextMessage(context))
        openChatID = chatID
        AppNavigator.shared.show(.ai)
        answer(chatID)
    }

    func send(_ text: String, images: [Data] = [], in chatID: String) {
        guard var chat = chat(chatID), streamingChatID == nil else { return }
        let imageIDs = images.compactMap { AIImageStore.save($0) }
        chat.messages.append(AIChatMessage(role: .user, text: text, imageIDs: imageIDs.isEmpty ? nil : imageIDs))
        chat.updatedAt = Date().timeIntervalSince1970
        history.upsert(chat)
        fileStore.save(history)
        answer(chatID)
    }

    func regenerate(_ chatID: String) {
        guard var chat = chat(chatID), streamingChatID == nil else { return }
        if chat.messages.last?.role == .assistant { chat.messages.removeLast() }
        history.upsert(chat)
        answer(chatID)
    }

    func stop() {
        task?.cancel()
    }

    private func answer(_ chatID: String) {
        let settings = AISettings.shared
        guard settings.isConfigured else {
            failure = UIL10n.string("Choose a provider and model first.")
            return
        }
        if settings.budget == .reached {
            failure = UIL10n.string("The monthly token limit is reached.")
            return
        }
        failure = nil
        streamingChatID = chatID
        task = Task { await run(chatID, settings: settings) }
    }

    private func run(_ chatID: String, settings: AISettings) async {
        defer { streamingChatID = nil }
        guard var chat = chat(chatID) else { return }
        var reply = AIChatMessage(role: .assistant, text: "")
        do {
            for try await event in try await events(chat.messages, settings: settings) {
                apply(event, to: &reply, settings: settings)
                publish(reply, in: &chat)
            }
        } catch is CancellationError {
        } catch {
            failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        if reply.text.isEmpty { chat.messages.removeAll { $0.id == reply.id } }
        history.upsert(chat)
        fileStore.save(history)
    }

    private func apply(_ event: AIStreamEvent, to reply: inout AIChatMessage, settings: AISettings) {
        switch event {
        case .text(let piece): reply.text += piece
        case .usage(let input, let output):
            reply.inputTokens = input
            reply.outputTokens = output
            settings.record(input: input, output: output)
        case .done, .failure: break
        }
    }

    private func publish(_ reply: AIChatMessage, in chat: inout AIChat) {
        chat.messages.removeAll { $0.id == reply.id }
        chat.messages.append(reply)
        chat.updatedAt = Date().timeIntervalSince1970
        history.upsert(chat)
    }

    /// The answer's events, from the device or over the network
    private func events(_ messages: [AIChatMessage], settings: AISettings) async throws
        -> AsyncThrowingStream<AIStreamEvent, Error> {
        if settings.isOnDevice {
            let wire = messages.map { AIMessage(role: $0.role, content: $0.text) }
            return AIOnDevice.stream(system: AIPrompts.systemPrompt(languageName: AILanguage.name), messages: wire)
        }
        let request = try await makeRequest(messages, settings: settings)
        return AIChatClient.stream(request, format: settings.resolvedConfig().format)
    }

    private func makeRequest(_ messages: [AIChatMessage], settings: AISettings) async throws -> AIHTTPRequest {
        var baseURL: String?
        if settings.isOllama { baseURL = try await localBaseURL(settings) }
        let config = settings.resolvedConfig(baseURL: baseURL)
        let wire = messages.map {
            AIMessage(role: $0.role, content: $0.text, images: AIImageStore.wire($0.imageIDs))
        }
        return AIRequestBuilder.build(config: config, apiKey: settings.apiKey(for: settings.providerID),
                                      system: AIPrompts.systemPrompt(languageName: AILanguage.name),
                                      messages: wire)
    }

    private func localBaseURL(_ settings: AISettings) async throws -> String {
        if let id = UUID(uuidString: settings.ollamaServerID),
           let deployment = ((try? FileDeploymentStore().load()) ?? []).first(where: { $0.id == id }) {
            return try await AIOllamaTunnel.baseURL(for: deployment)
        }
        let url = settings.ollamaURL.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { throw AIChatFailure(message: UIL10n.string("Choose where Ollama runs.")) }
        return url.hasSuffix("/v1") ? url : url + "/v1"
    }
}

enum AILanguage {
    static var name: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }
}
