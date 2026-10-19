package com.skaymer.gryonixnexus.app.licensing

import com.skaymer.gryonixnexus.app.secrets.SecretStore
import com.skaymer.gryonixnexus.app.servers.DemoDeployments
import com.skaymer.gryonixnexus.servercontrol.Deployment
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

sealed interface LicenseStatus {
    data object Demo : LicenseStatus
    data class Active(val plan: LicensePlan, val expires: Long?) : LicenseStatus
    data object Expired : LicenseStatus
}

/** What this copy may do, kept in the secret store. */
class LicenseStore(
    private val secrets: SecretStore,
    private val deviceUid: () -> String,
    private val deviceName: String = "Android",
    private val api: LicenseApi = LicenseApi(),
    private val publicKey: String = LicenseTokens.PRODUCTION_KEY,
    private val clock: () -> Long = { System.currentTimeMillis() / 1000 },
) {
    private val _status = MutableStateFlow<LicenseStatus>(LicenseStatus.Demo)
    val status: StateFlow<LicenseStatus> = _status
    private val _code = MutableStateFlow<String?>(null)
    val code: StateFlow<String?> = _code

    init {
        reload()
    }

    fun reload() {
        _code.value = secrets.string(CODE)
        val token = storedToken()
        val everActive = secrets.string(EVER_ACTIVE) != null
        _status.value = when {
            token != null -> LicenseStatus.Active(token.plan, token.expires)
            everActive -> LicenseStatus.Expired
            else -> LicenseStatus.Demo
        }
        if (token != null) secrets.setString(EVER_ACTIVE, "1")
        LicenseGate.unlocked = token != null
        LicenseGate.everActive = everActive || token != null
        LicenseGate.status.value = _status.value
    }

    /** Activates this device; returns the failure, or null. */
    suspend fun activate(input: String): LicenseFailure? {
        val code = ActivationCode.normalize(input) ?: return LicenseFailure.UNKNOWN_CODE
        return try {
            store(api.activate(code, deviceUid(), deviceName), code)
            null
        } catch (failure: LicenseApiException) {
            failure.failure
        }
    }

    suspend fun removeFromThisDevice() {
        _code.value?.let { code -> runCatching { api.deactivate(code, deviceUid()) } }
        secrets.deleteSecret(TOKEN)
        secrets.deleteSecret(CODE)
        reload()
    }

    /** Renews a subscription token in its last week. */
    suspend fun refreshIfDue() {
        sendUsedMark()
        val code = _code.value ?: return
        val token = storedToken()
        if (token != null && (token.expires == null || token.expires - clock() > RENEW_WINDOW)) return
        runCatching { store(api.activate(code, deviceUid(), deviceName), code) }
        reload()
    }

    suspend fun noteFirstGeneration() {
        if (secrets.string(USED_SENT) != null) return
        secrets.setString(USED_PENDING, "1")
        sendUsedMark()
    }

    private suspend fun sendUsedMark() {
        if (secrets.string(USED_PENDING) == null) return
        val code = _code.value ?: return
        if (runCatching { api.markUsed(code, deviceUid()) }.isFailure) return
        secrets.deleteSecret(USED_PENDING)
        secrets.setString(USED_SENT, "1")
    }

    fun thisDevice(): String = deviceUid()

    suspend fun devices(): LicenseDeviceList? = _code.value?.let { runCatching { api.devices(it) }.getOrNull() }

    suspend fun removeDevice(device: String) {
        _code.value?.let { runCatching { api.deactivate(it, device) } }
    }

    private fun store(grant: LicenseGrant, code: String) {
        val token = grant.token ?: throw LicenseApiException(LicenseFailure.REJECTED)
        try {
            LicenseTokens.verify(token, deviceUid(), clock(), publicKey)
        } catch (_: LicenseTokenError.OtherProduct) {
            throw LicenseApiException(LicenseFailure.WRONG_PRODUCT)
        } catch (_: Exception) {
            throw LicenseApiException(LicenseFailure.REJECTED)
        }
        secrets.setString(TOKEN, token)
        secrets.setString(CODE, grant.code ?: code)
        reload()
    }

    private fun storedToken(): LicenseToken? {
        val text = secrets.string(TOKEN) ?: return null
        return runCatching { LicenseTokens.verify(text, deviceUid(), clock(), publicKey) }.getOrNull()
    }

    private companion object {
        const val TOKEN = "license-token"
        const val CODE = "license-code"
        const val EVER_ACTIVE = "license-ever-active"
        const val USED_PENDING = "license-used-pending"
        const val USED_SENT = "license-used-sent"
        const val RENEW_WINDOW = 7L * 24 * 3600
    }
}

class LicenseLockedException(val renew: Boolean) : Exception(if (renew) "subscription" else "full version")

/** Refuses real servers without a license. */
object LicenseGate {
    @Volatile var unlocked = false
    @Volatile var everActive = false
    val status = MutableStateFlow<LicenseStatus>(LicenseStatus.Demo)

    /** Throws for a real server while locked. */
    fun check(deployment: Deployment) = check(deployment.id)

    fun check(deploymentID: String) {
        if (unlocked || DemoDeployments.isDemoID(deploymentID)) return
        throw LicenseLockedException(renew = everActive)
    }
}

/** The lock dialog request, raised from anywhere. */
object LicensePrompt {
    val showing = MutableStateFlow(false)

    /** True when unlocked; otherwise raises the dialog. */
    fun allow(deployment: Deployment? = null): Boolean = allow(deployment?.id)

    /** Same, by server id; demo servers always pass. */
    fun allow(serverID: String?): Boolean {
        if (LicenseGate.unlocked) return true
        if (serverID != null && DemoDeployments.isDemoID(serverID)) return true
        showing.value = true
        return false
    }
}
