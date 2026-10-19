package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.app.secrets.DNSCredential
import com.skaymer.gryonixnexus.app.secrets.DNSCredentialTokenStore
import com.skaymer.gryonixnexus.app.secrets.DNSCredentials
import com.skaymer.gryonixnexus.core.DNSPublishingProvider
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class DNSProviderPublishModel(
    private val credentials: DNSCredentials,
    private val tokens: DNSCredentialTokenStore,
    initialProviderKind: DNSProviderKind = DNSProviderKind.CLOUDFLARE,
    /** Swapped in tests — a real run touches the network */
    private val providerFactory: (DNSProviderKind, String) -> DNSPublishingProvider =
        { kind, token -> kind.makeProvider(token) },
) {
    data class State(
        val credentialID: String?,
        /** The saved tokens for [providerKind] — what the picker draws */
        val saved: List<DNSCredential> = emptyList(),
        val providerKind: DNSProviderKind = DNSProviderKind.CLOUDFLARE,
        val token: String = "",
        val lines: List<String> = emptyList(),
        val isWorking: Boolean = false,
        val failed: Boolean = false,
    )

    private val _state = MutableStateFlow(
        State(credentialID = credentials.selectedID, providerKind = initialProviderKind)
    )
    val state: StateFlow<State> = _state.asStateFlow()

    fun loadStoredToken() {
        if (_state.value.token.isNotEmpty()) return
        loadTokenForCurrentProvider()
    }

    fun loadToken(id: String?) {
        val credential = _state.value.saved.firstOrNull { it.id == id }
        _state.value = _state.value.copy(
            credentialID = id,
            token = credential?.let { tokens.token(it) }.orEmpty(),
        )
    }

    fun selectProvider(kind: DNSProviderKind) {
        _state.value = _state.value.copy(providerKind = kind)
        loadTokenForCurrentProvider()
    }

    private fun loadTokenForCurrentProvider() {
        credentials.adoptStoredTokensIfNeeded()
        val kind = _state.value.providerKind
        val saved = credentials.all.filter { it.kind == kind }
        val chosen = saved.firstOrNull { it.id == _state.value.credentialID } ?: saved.firstOrNull()
        _state.value = _state.value.copy(saved = saved)
        loadToken(chosen?.id)
    }

    fun setToken(value: String) {
        _state.value = _state.value.copy(token = value)
    }

    /** Verifies the token, then applies every zone */
    suspend fun publish(zones: List<ConfigurationExport.DNSZone>) {
        val kind = _state.value.providerKind
        val token = _state.value.token
        _state.value = _state.value.copy(isWorking = true, failed = false, lines = emptyList())

        val provider = providerFactory(kind, token)
        try {
            provider.verifyToken()
            val target = _state.value.saved.firstOrNull { it.id == _state.value.credentialID }
                ?: credentials.add(kind.displayName, kind)
            tokens.setToken(target, token)
            _state.value = _state.value.copy(
                saved = credentials.all.filter { it.kind == kind },
                credentialID = target.id,
            )
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Exception) {
            _state.value = _state.value.copy(
                isWorking = false,
                failed = true,
                lines = listOf(error.message ?: error::class.simpleName.orEmpty()),
            )
            return
        }

        val lines = mutableListOf<String>()
        var failed = false
        for (zone in zones) {
            try {
                val outcomes = provider.publishReportingOutcomes(zone.records, zone.domain)
                val summary = DNSPublishSummary.summarize(zone.domain, outcomes)
                lines += summary.lines
                if (summary.failed) failed = true
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                failed = true
                lines += "${zone.domain}: ${error.message ?: error::class.simpleName.orEmpty()}"
            }
        }
        _state.value = _state.value.copy(isWorking = false, failed = failed, lines = lines)
    }

    companion object {
        /** Disabled while empty, working, or with nothing to publish */
        fun canPublish(token: String, isWorking: Boolean, hasZones: Boolean): Boolean =
            token.isNotEmpty() && !isWorking && hasZones
    }
}
