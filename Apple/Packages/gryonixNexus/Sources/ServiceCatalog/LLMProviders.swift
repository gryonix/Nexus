public struct LLMProvider: Sendable, Hashable, Identifiable {
    public let id: String
    /// What the person pasting a key calls it
    public let displayName: String
    /// The environment variable the provider's own SDK reads
    public let environmentKey: String
    /// Where somebody gets the key
    public let consoleURL: String

    public init(id: String, displayName: String, environmentKey: String, consoleURL: String) {
        self.id = id
        self.displayName = displayName
        self.environmentKey = environmentKey
        self.consoleURL = consoleURL
    }

    /// The `VaultEntry.service_secret` value that carries this provider's key
    public var vaultSecretID: String { "\(ServiceID.liteLLM.rawValue)/\(id)" }

    public static let all: [LLMProvider] = [
        LLMProvider(id: "openai", displayName: "OpenAI",
                    environmentKey: "OPENAI_API_KEY",
                    consoleURL: "https://platform.openai.com/api-keys"),
        LLMProvider(id: "anthropic", displayName: "Anthropic",
                    environmentKey: "ANTHROPIC_API_KEY",
                    consoleURL: "https://console.anthropic.com/settings/keys"),
        LLMProvider(id: "deepseek", displayName: "DeepSeek",
                    environmentKey: "DEEPSEEK_API_KEY",
                    consoleURL: "https://platform.deepseek.com/api_keys"),
        LLMProvider(id: "gemini", displayName: "Google Gemini",
                    environmentKey: "GEMINI_API_KEY",
                    consoleURL: "https://aistudio.google.com/apikey"),
        LLMProvider(id: "groq", displayName: "Groq",
                    environmentKey: "GROQ_API_KEY",
                    consoleURL: "https://console.groq.com/keys"),
        LLMProvider(id: "mistral", displayName: "Mistral",
                    environmentKey: "MISTRAL_API_KEY",
                    consoleURL: "https://console.mistral.ai/api-keys"),
        LLMProvider(id: "openrouter", displayName: "OpenRouter",
                    environmentKey: "OPENROUTER_API_KEY",
                    consoleURL: "https://openrouter.ai/keys"),
        LLMProvider(id: "xai", displayName: "xAI",
                    environmentKey: "XAI_API_KEY",
                    consoleURL: "https://console.x.ai")
    ]

    public static func provider(id: String) -> LLMProvider? {
        all.first { $0.id == id }
    }

    public static func provider(vaultSecretID: String) -> LLMProvider? {
        all.first { $0.vaultSecretID == vaultSecretID }
    }
}
