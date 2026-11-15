package com.skaymer.gryonixnexus.app.dns

import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import com.skaymer.gryonixnexus.catalog.ServiceRegistry
import com.skaymer.gryonixnexus.servercontrol.DKIMExport
import com.skaymer.gryonixnexus.servercontrol.DKIMManaging
import com.skaymer.gryonixnexus.servercontrol.DKIMRecord
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** What the DKIM screen is showing about one server */
data class DKIMState(
    val records: List<DKIMRecord> = emptyList(),
    val isLoading: Boolean = false,
    val hasAnswered: Boolean = false,
    val errorMessage: String? = null,
) {
    val saysTheKeyIsNotReady: Boolean
        get() = hasAnswered && errorMessage == null && !isLoading && records.isEmpty()

    fun copyText(): String = DKIMExport.recordsText(records)
}

/** The DKIM records the server generated */
class DKIMViewModel(
    private val scope: CoroutineScope,
    private val records: suspend (Deployment) -> DKIMManaging,
    private val release: suspend (Deployment) -> Unit = {},
) {
    private val _state = MutableStateFlow(DKIMState())
    val state: StateFlow<DKIMState> = _state.asStateFlow()

    fun load(deployment: Deployment) {
        if (DemoDeployments.isDemoID(deployment.id)) {
            _state.value = DKIMState(records = listOf(demoRecord(deployment)), hasAnswered = true)
            return
        }
        scope.launch {
            _state.value = _state.value.copy(isLoading = true, errorMessage = null)
            try {
                _state.value = DKIMState(
                    records = records(deployment).fetchRecords(),
                    hasAnswered = true,
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                release(deployment)
                _state.value = _state.value.copy(
                    isLoading = false,
                    hasAnswered = true,
                    errorMessage = failure.message ?: failure::class.simpleName,
                )
            }
        }
    }

    /** An invented key for the demo fleet */
    private fun demoRecord(deployment: Deployment) = DKIMRecord(
        name = "dkim._domainkey.${deployment.domain}",
        value = "v=DKIM1;k=rsa;p=" + "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A".repeat(6),
    )

    fun reset() {
        _state.value = DKIMState()
    }

    companion object {
        /** Whether this server sends mail at all */
        fun hasMailEngine(deployment: Deployment): Boolean =
            ServiceRegistry.mailEngine(deployment.services) != null
    }
}
