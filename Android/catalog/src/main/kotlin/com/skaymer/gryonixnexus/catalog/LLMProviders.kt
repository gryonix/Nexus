package com.skaymer.gryonixnexus.catalog

/** The model providers the gateway can hold a key for */
data class LLMProvider(
    /** Stable id, and the second half of `service_secret` */
    val id: String,
    /** What the person pasting a key calls it */
    val displayName: String,
    val environmentKey: String,
    val consoleURL: String,
) {
    /** The `VaultEntry.service_secret` value that carries this provider's key */
    val vaultSecretID: String get() = "${ServiceID.LITE_LLM.rawValue}/$id"

    companion object {
        val ALL: List<LLMProvider> = listOf(
            LLMProvider("openai", "OpenAI", "OPENAI_API_KEY",
                "https://platform.openai.com/api-keys"),
            LLMProvider("anthropic", "Anthropic", "ANTHROPIC_API_KEY",
                "https://console.anthropic.com/settings/keys"),
            LLMProvider("deepseek", "DeepSeek", "DEEPSEEK_API_KEY",
                "https://platform.deepseek.com/api_keys"),
            LLMProvider("gemini", "Google Gemini", "GEMINI_API_KEY",
                "https://aistudio.google.com/apikey"),
            LLMProvider("groq", "Groq", "GROQ_API_KEY",
                "https://console.groq.com/keys"),
            LLMProvider("mistral", "Mistral", "MISTRAL_API_KEY",
                "https://console.mistral.ai/api-keys"),
            LLMProvider("openrouter", "OpenRouter", "OPENROUTER_API_KEY",
                "https://openrouter.ai/keys"),
            LLMProvider("xai", "xAI", "XAI_API_KEY",
                "https://console.x.ai"),
        )

        fun byID(id: String): LLMProvider? = ALL.firstOrNull { it.id == id }

        fun byVaultSecretID(secret: String): LLMProvider? =
            ALL.firstOrNull { it.vaultSecretID == secret }
    }
}
