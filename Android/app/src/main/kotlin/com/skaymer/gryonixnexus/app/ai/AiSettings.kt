package com.skaymer.gryonixnexus.app.ai

import com.skaymer.gryonixnexus.aiassistant.AIBudgetState
import com.skaymer.gryonixnexus.aiassistant.AIProviderConfig
import com.skaymer.gryonixnexus.aiassistant.AITokenLedger
import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.shell.SettingsStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

data class AiConfig(
    val providerId: String = "",
    val model: String = "",
    val ollamaServerId: String = "",
    val ollamaUrl: String = "",
    val monthlyLimit: Int = 0,
    val agreed: Boolean = false,
    val usedThisMonth: Int = 0,
) {
    val isConfigured: Boolean get() = providerId.isNotEmpty() && model.isNotEmpty()
    val isLocal: Boolean get() = providerId == AIProviderConfig.OLLAMA_ID
    val budget: AIBudgetState
        get() = if (isLocal) AIBudgetState.UNLIMITED else AITokenLedger.state(usedThisMonth, monthlyLimit)
}

/** Provider choice, limits and notices; kept on this device only. */
class AiSettings(
    private val store: SettingsStore,
    private val secrets: SecretStore,
    private val now: () -> Long = { System.currentTimeMillis() },
) {
    private val ledger = AITokenLedger(readLedger())
    private val _config = MutableStateFlow(read())
    val config: StateFlow<AiConfig> = _config.asStateFlow()

    fun update(change: (AiConfig) -> AiConfig) {
        val next = change(_config.value)
        store.setString(PROVIDER, next.providerId)
        store.setString(MODEL, next.model)
        store.setString(SERVER, next.ollamaServerId)
        store.setString(URL, next.ollamaUrl)
        store.setString(LIMIT, next.monthlyLimit.toString())
        store.setBoolean(AGREED, next.agreed)
        _config.value = next
    }

    fun apiKey(provider: String): String = secrets.string("ai.key.$provider").orEmpty()

    fun setApiKey(provider: String, key: String) {
        val trimmed = key.trim()
        if (trimmed.isEmpty()) secrets.deleteSecret("ai.key.$provider") else secrets.setString("ai.key.$provider", trimmed)
    }

    fun hasSeenCloudNotice(provider: String): Boolean = provider in (store.stringList(CLOUD_SEEN) ?: emptyList())

    fun markCloudNoticeSeen(provider: String) {
        store.setStringList(CLOUD_SEEN, ((store.stringList(CLOUD_SEEN) ?: emptyList()) + provider).distinct())
    }

    val hasSeenLocalNotice: Boolean get() = store.boolean(LOCAL_SEEN) == true

    fun markLocalNoticeSeen() = store.setBoolean(LOCAL_SEEN, true)

    fun record(input: Int, output: Int) {
        if (_config.value.isLocal) return
        ledger.add(input + output, now())
        store.setString(LEDGER, Json.encodeToString(MapSerializer(String.serializer(), Int.serializer()), ledger.snapshot()))
        _config.value = _config.value.copy(usedThisMonth = ledger.used(now()))
    }

    private fun read() = AiConfig(
        providerId = store.string(PROVIDER).orEmpty(),
        model = store.string(MODEL).orEmpty(),
        ollamaServerId = store.string(SERVER).orEmpty(),
        ollamaUrl = store.string(URL).orEmpty(),
        monthlyLimit = store.string(LIMIT)?.toIntOrNull() ?: 0,
        agreed = store.boolean(AGREED) == true,
        usedThisMonth = ledger.used(now()),
    )

    private fun readLedger(): Map<String, Int> = store.string(LEDGER)
        ?.let { runCatching { Json.decodeFromString(MapSerializer(String.serializer(), Int.serializer()), it) }.getOrNull() }
        .orEmpty()

    private companion object {
        const val PROVIDER = "ai.provider"
        const val MODEL = "ai.model"
        const val SERVER = "ai.ollamaServer"
        const val URL = "ai.ollamaURL"
        const val LIMIT = "ai.monthlyLimit"
        const val AGREED = "ai.agreed"
        const val CLOUD_SEEN = "ai.cloudSeen"
        const val LOCAL_SEEN = "ai.localSeen"
        const val LEDGER = "ai.ledger"
    }
}
