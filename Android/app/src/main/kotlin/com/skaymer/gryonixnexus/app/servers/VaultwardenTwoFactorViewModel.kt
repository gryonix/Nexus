package com.skaymer.gryonixnexus.app.servers

import com.skaymer.gryonixnexus.agentcontrol.AgentVaultwardenOperations
import com.skaymer.gryonixnexus.agentcontrol.VaultwardenTwoFactorStatus
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Which Vaultwarden accounts have no two-factor login, per server */
class VaultwardenTwoFactorViewModel(
    private val scope: CoroutineScope,
    private val operations: suspend (Deployment) -> AgentVaultwardenOperations,
) {
    /** Null means the agent gave no answer */
    private val _state = MutableStateFlow<Map<String, VaultwardenTwoFactorStatus?>>(emptyMap())
    val state: StateFlow<Map<String, VaultwardenTwoFactorStatus?>> = _state.asStateFlow()

    fun load(deployment: Deployment) {
        scope.launch {
            val status = try {
                operations(deployment).twoFactor()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (failure: Exception) {
                null
            }
            _state.value = _state.value + (deployment.id to status)
        }
    }

    companion object {
        /** Vaultwarden runs here with an agent */
        fun canShow(deployment: Deployment): Boolean =
            deployment.usesAgent && ServiceID.VAULTWARDEN in deployment.services
    }
}
