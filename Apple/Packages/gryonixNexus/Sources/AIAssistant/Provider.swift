import Foundation

/// Which wire format a provider speaks.
public enum AIWireFormat: String, Codable, Sendable {
    case openAI
    case anthropic
}

/// The provider and model a chat talks to.
public struct AIProviderConfig: Codable, Equatable, Sendable {
    public static let ollamaID = "ollama"
    public static let onDeviceID = "apple"
    public static let onDeviceModel = "on-device"

    public var providerID: String
    public var model: String
    public var baseURL: String

    public init(providerID: String, model: String, baseURL: String? = nil) {
        self.providerID = providerID
        self.model = model
        self.baseURL = baseURL ?? Self.defaultBaseURL(providerID) ?? ""
    }

    public var isLocal: Bool { providerID == Self.ollamaID || providerID == Self.onDeviceID }
    public var format: AIWireFormat { providerID == "anthropic" ? .anthropic : .openAI }

    public static func defaultBaseURL(_ id: String) -> String? {
        [
            "openai": "https://api.openai.com/v1",
            "anthropic": "https://api.anthropic.com/v1",
            "deepseek": "https://api.deepseek.com/v1",
            "gemini": "https://generativelanguage.googleapis.com/v1beta/openai",
            "groq": "https://api.groq.com/openai/v1",
            "mistral": "https://api.mistral.ai/v1",
            "openrouter": "https://openrouter.ai/api/v1",
            "xai": "https://api.x.ai/v1"
        ][id]
    }

    public static func suggestedModel(_ id: String) -> String {
        [
            "openai": "gpt-4o-mini", "anthropic": "claude-haiku-4-5",
            "deepseek": "deepseek-chat", "gemini": "gemini-2.0-flash",
            "groq": "llama-3.3-70b-versatile", "mistral": "mistral-small-latest",
            "openrouter": "openai/gpt-4o-mini", "xai": "grok-3-mini",
            "ollama": "llama3.2:3b",
            "apple": onDeviceModel
        ][id] ?? ""
    }
}

public enum AIRole: String, Codable, Sendable {
    case system, user, assistant
}

/// A picture attached to a message, base64-encoded
public struct AIImage: Equatable, Sendable {
    public var mediaType: String
    public var base64: String

    public init(mediaType: String, base64: String) {
        self.mediaType = mediaType
        self.base64 = base64
    }
}

public struct AIMessage: Equatable, Sendable {
    public var role: AIRole
    public var content: String
    public var images: [AIImage]

    public init(role: AIRole, content: String, images: [AIImage] = []) {
        self.role = role
        self.content = content
        self.images = images
    }
}

public struct AIHTTPRequest: Equatable, Sendable {
    public var url: String
    public var headers: [String: String]
    public var body: Data
}

/// Builds the streaming chat request for a provider.
public enum AIRequestBuilder {
    public static let anthropicVersion = "2023-06-01"
    public static let maxTokens = 2048

    public static func build(config: AIProviderConfig, apiKey: String?, system: String,
                             messages: [AIMessage]) -> AIHTTPRequest {
        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        switch config.format {
        case .anthropic:
            return anthropic(config, base, apiKey ?? "", system, messages)
        case .openAI:
            return openAI(config, base, apiKey, system, messages)
        }
    }

    private static func openAI(_ config: AIProviderConfig, _ base: String, _ key: String?,
                               _ system: String, _ messages: [AIMessage]) -> AIHTTPRequest {
        var headers = ["Content-Type": "application/json"]
        if let key, !key.isEmpty { headers["Authorization"] = "Bearer \(key)" }
        let all = [AIMessage(role: .system, content: system)] + messages
        let body: [String: Any] = [
            "model": config.model,
            "stream": true,
            "stream_options": ["include_usage": true],
            "messages": all.map { ["role": $0.role.rawValue, "content": openAIContent($0)] }
        ]
        return AIHTTPRequest(url: base + "/chat/completions", headers: headers, body: encode(body))
    }

    private static func anthropic(_ config: AIProviderConfig, _ base: String, _ key: String,
                                  _ system: String, _ messages: [AIMessage]) -> AIHTTPRequest {
        let headers = ["Content-Type": "application/json", "x-api-key": key,
                       "anthropic-version": anthropicVersion]
        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": maxTokens,
            "stream": true,
            "system": system,
            "messages": messages.filter { $0.role != .system }
                .map { ["role": $0.role.rawValue, "content": anthropicContent($0)] }
        ]
        return AIHTTPRequest(url: base + "/messages", headers: headers, body: encode(body))
    }

    /// Plain text, or text plus image_url parts
    private static func openAIContent(_ message: AIMessage) -> Any {
        guard !message.images.isEmpty else { return message.content }
        let images: [[String: Any]] = message.images.map {
            ["type": "image_url", "image_url": ["url": "data:\($0.mediaType);base64,\($0.base64)"]]
        }
        return [["type": "text", "text": message.content]] + images
    }

    /// Plain text, or image blocks followed by the text
    private static func anthropicContent(_ message: AIMessage) -> Any {
        guard !message.images.isEmpty else { return message.content }
        let images: [[String: Any]] = message.images.map {
            ["type": "image", "source": ["type": "base64", "media_type": $0.mediaType, "data": $0.base64]]
        }
        return images + [["type": "text", "text": message.content]]
    }

    private static func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}
