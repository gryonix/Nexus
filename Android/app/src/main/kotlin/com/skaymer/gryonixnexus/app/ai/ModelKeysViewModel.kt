package com.skaymer.gryonixnexus.app.ai

import com.skaymer.gryonixnexus.agentcontrol.AgentVaultOperations
import com.skaymer.gryonixnexus.catalog.LLMProvider
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.app.access.InstallReportImport
import gryonixnexusd.v1.VaultEntry
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class ModelKeysViewModel(
    private val scope: CoroutineScope,
    private val vault: suspend (Deployment) -> AgentVaultOperations?,
    private val deviceUID: () -> String = { "" },
    private val now: () -> Long = { System.currentTimeMillis() },
    private val release: suspend (Deployment) -> Unit = {},
) {
    data class State(
        val isLoading: Boolean = true,
        val isSaving: Boolean = false,
        /** Provider ids the server already holds a key for */
        val stored: Set<String> = emptySet(),
        /** True after a save that reached the server */
        val saved: Boolean = false,
        val errorMessage: String? = null,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    private var job: Job? = null

    fun load(deployment: Deployment) {
        job?.cancel()
        _state.value = State()
        job = scope.launch {
            val operations = vault(deployment) ?: run {
                _state.value = State(isLoading = false, errorMessage = NO_AGENT)
                return@launch
            }
            try {
                val remote = operations.snapshot().entries
                _state.value = State(
                    isLoading = false,
                    stored = remote
                        .filter { !it.deleted }
                        .mapNotNull { LLMProvider.byVaultSecretID(it.service_secret)?.id }
                        .toSet(),
                )
            } catch (error: Throwable) {
                _state.value = State(isLoading = false, errorMessage = error.message ?: FAILURE)
            } finally {
                release(deployment)
            }
        }
    }

    fun save(deployment: Deployment, typed: Map<String, String>) {
        job?.cancel()
        job = scope.launch {
            _state.value = _state.value.copy(isSaving = true, saved = false, errorMessage = null)
            val stamp = now()
            val writer = deviceUID()
            val running = deployment.hostRunning(ServiceID.LITE_LLM)
            val host = InstallReportImport.hosts(deployment)
                .firstOrNull { it.second == running }?.first ?: "single"
            val entries = LLMProvider.ALL.mapNotNull { provider ->
                val key = typed[provider.id].orEmpty().trim()
                if (key.isEmpty()) null else entry(host, provider, key, stamp, writer)
            }
            if (entries.isEmpty()) {
                _state.value = _state.value.copy(isSaving = false)
                return@launch
            }
            val operations = vault(deployment) ?: run {
                _state.value = _state.value.copy(isSaving = false, errorMessage = NO_AGENT)
                return@launch
            }
            try {
                operations.save(entries)
                _state.value = _state.value.copy(
                    isSaving = false,
                    saved = true,
                    stored = _state.value.stored +
                        entries.mapNotNull { LLMProvider.byVaultSecretID(it.service_secret)?.id },
                )
            } catch (error: Throwable) {
                _state.value = _state.value.copy(
                    isSaving = false,
                    errorMessage = error.message ?: FAILURE,
                )
            } finally {
                release(deployment)
            }
        }
    }

    fun reset() {
        job?.cancel()
        _state.value = State()
    }

    companion object {
        /** Stable markers the screen turns into its own sentences */
        const val NO_AGENT = "no-agent"
        const val FAILURE = "failed"

        fun canManage(deployment: Deployment): Boolean =
            deployment.usesAgent && deployment.services.contains(ServiceID.LITE_LLM)

        /** One provider's key, as a vault row */
        fun entry(
            host: String,
            provider: LLMProvider,
            key: String,
            updatedAt: Long,
            updatedBy: String,
        ): VaultEntry {
            val title = "LiteLLM: ${provider.displayName}"
            return VaultEntry(
                id = "$host|$title",
                host = host,
                title = title,
                website = provider.consoleURL,
                login = "",
                password = "",
                token = key.trim(),
                updated_at = updatedAt,
                updated_by = updatedBy,
                service_secret = provider.vaultSecretID,
            )
        }
    }
}
